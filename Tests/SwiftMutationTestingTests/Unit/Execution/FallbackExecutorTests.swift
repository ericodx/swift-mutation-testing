import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("FallbackExecutor")
struct FallbackExecutorTests {
    @Test("Given SPM project type with successful build, when execute called, then results are returned")
    func spmFallbackBuildSuccessReturnsResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let config = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)

        let launcher = MockProcessLauncher(exitCode: 0)
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let executor = FallbackExecutor(deps: deps, configuration: config)
        let results = try await executor.execute(input: input, pool: pool)

        #expect(results.count == 1)
    }

    @Test("Given an SPM fallback build that leaves test bundles, when execute called, then the tests run from them")
    func spmFallbackRunsTheBundlesItBuilt() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let launcher = TwoBundleLauncher()
        let pool = makeSimulatorPool()
        try await pool.setUp()
        let mutant = makeMutantDescriptor(
            id: "m0", filePath: sourceFile.path, originalText: "true", mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement", replacementKind: .booleanLiteral,
            description: "true → false", isSchematizable: true
        )
        let input = makeRunnerInput(
            projectPath: dir.path, projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await FallbackExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path),
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)
        ).execute(input: input, pool: pool)

        #expect(results.count == 1)
        #expect(Set(await launcher.runs.map(\.bundle)).isSubset(of: Set(TwoBundleLauncher.bundles)))
        #expect(!(await launcher.runs.isEmpty))
    }

    @Test("Given the fallback build times out, when execute called, then mutants are timeout and nothing is cached")
    func fallbackBuildTimeoutIsNotRecordedAsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let config = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)
        let cachePath = dir.appendingPathComponent("cache.json").path
        let deps = makeExecutionDeps(
            launcher: MockProcessLauncher(exitCode: SPMResultParser.timedOutExitCode),
            cacheStorePath: cachePath
        )

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let results = try await FallbackExecutor(deps: deps, configuration: config)
            .execute(input: input, pool: pool)

        #expect(results.map(\.status) == [.timeout])
        #expect(await deps.cacheStore.result(for: MutantCacheKey.make(for: mutant)) == nil)
    }

    @Test("Given the fallback build fails, when execute called with a log directory, then each mutant's log says why")
    func aFailedFallbackBuildIsLogged() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let logs = dir.appendingPathComponent("logs")

        let config = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, keepLogsPath: logs.path)
        let deps = makeExecutionDeps(
            launcher: MockProcessLauncher(exitCode: 1), cacheStorePath: dir.appendingPathComponent("cache.json").path
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()
        let mutant = makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)

        let results = try await FallbackExecutor(deps: deps, configuration: config).execute(
            input: makeRunnerInput(
                projectPath: dir.path,
                projectType: .spm,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = 1 -")],
                mutants: [mutant]
            ),
            pool: pool
        )

        #expect(results.map(\.status) == [.unviable])
        let log = try String(contentsOf: logs.appendingPathComponent("m0.log"), encoding: .utf8)
        #expect(log.contains("Build failed"))
    }

    @Test(
        "Given a per-file fallback build, when execute called, then it is bounded by the build timeout",
        arguments: [
            (ProjectType.spm, "build"),
            (ProjectType.xcode(scheme: "App", destination: "platform=macOS"), "build-for-testing"),
        ]
    )
    func fallbackBuildUsesBuildTimeout(projectType: ProjectType, verb: String) async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        let config = makeRunnerConfiguration(
            projectPath: dir.path, projectType: projectType, timeout: 30, buildTimeout: 240
        )
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: projectType,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [
                makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)
            ]
        )

        _ = try? await FallbackExecutor(deps: deps, configuration: config).execute(input: input, pool: pool)

        #expect(await launcher.timeouts(forCommandStartingWith: verb) == [240])
    }

    @Test("Given a schematized file no mutant belongs to, when execute called, then it produces no results")
    func aFileWithoutMutantsProducesNoResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        let untouched = dir.appendingPathComponent("Bar.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "let y = true".write(to: untouched, atomically: true, encoding: .utf8)

        let deps = makeExecutionDeps(
            launcher: MockProcessLauncher(exitCode: 0),
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false"),
                SchematizedFile(originalPath: untouched.path, schematizedContent: "let y = false"),
            ],
            mutants: [
                makeMutantDescriptor(
                    id: "m0", filePath: sourceFile.path,
                    originalText: "true", mutatedText: "false",
                    operatorIdentifier: "BooleanLiteralReplacement",
                    replacementKind: .booleanLiteral, isSchematizable: true
                )
            ]
        )

        let results = try await FallbackExecutor(
            deps: deps, configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)
        ).execute(input: input, pool: pool)

        #expect(results.map(\.descriptor.id) == ["m0"])
    }

    @Test(
        "Given the fallback build is cancelled, when execute called, then the cancellation ends it and nothing is recorded"
    )
    func aCancelledFallbackBuildRecordsNothing() async throws {
        let fixture = try FailingBuildFixture(launcher: CancellingLauncher())
        defer { fixture.cleanUp() }

        await #expect(throws: CancellationError.self) {
            _ = try await fixture.execute()
        }
        #expect(await fixture.cachedResult() == nil)
    }

    @Test(
        "Given the fallback build cannot be started, when execute called, then the error ends it and nothing is recorded"
    )
    func aBuildThatCannotStartRecordsNothing() async throws {
        let fixture = try FailingBuildFixture(launcher: MockProcessLauncher(exitCode: 0, throwsOnCapture: true))
        defer { fixture.cleanUp() }

        await #expect(throws: CocoaError.self) {
            _ = try await fixture.execute()
        }
        #expect(await fixture.cachedResult() == nil)
    }

    @Test(
        "Given an Xcode fallback build that leaves no xctestrun, when execute called, then it fails instead of judging"
    )
    func aMissingXctestrunRecordsNothing() async throws {
        let fixture = try FailingBuildFixture(
            launcher: MockProcessLauncher(exitCode: 0),
            projectType: .xcode(scheme: "App", destination: "platform=macOS")
        )
        defer { fixture.cleanUp() }

        await #expect(throws: BuildError.xctestrunNotFound) {
            _ = try await fixture.execute()
        }
        #expect(await fixture.cachedResult() == nil)
    }

    // MARK: - Private

    private struct CancellingLauncher: ProcessLaunching {
        func launch(
            executableURL: URL, arguments: [String], workingDirectoryURL: URL, timeout: Double
        ) async throws -> Int32 {
            throw CancellationError()
        }

        func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String) {
            throw CancellationError()
        }
    }

    private struct FailingBuildFixture {
        let directory: URL
        let deps: ExecutionDeps
        let configuration: RunnerConfiguration
        let mutant: MutantDescriptor
        let sourceFile: URL

        init(launcher: any ProcessLaunching, projectType: ProjectType = .spm) throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            sourceFile = directory.appendingPathComponent("Foo.swift")
            try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
            configuration = makeRunnerConfiguration(projectPath: directory.path, projectType: projectType)
            deps = makeExecutionDeps(
                launcher: launcher, cacheStorePath: directory.appendingPathComponent("cache.json").path
            )
            mutant = makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)
        }

        func execute() async throws -> [ExecutionResult] {
            let pool = makeSimulatorPool()
            try await pool.setUp()
            return try await FallbackExecutor(deps: deps, configuration: configuration).execute(
                input: makeRunnerInput(
                    projectPath: directory.path,
                    projectType: configuration.build.projectType,
                    schematizedFiles: [
                        SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                    ],
                    mutants: [mutant]
                ),
                pool: pool
            )
        }

        func cachedResult() async -> ExecutionResult? {
            await deps.cacheStore.cachedResult(for: mutant)
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }
    }
}
