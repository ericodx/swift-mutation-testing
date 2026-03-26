import Foundation
import Testing

@testable import SwiftMutationTesting

private actor FallbackBuildSucceedingMock: ProcessLaunching {
    private var launchCount = 0

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        launchCount += 1
        if launchCount == 1 { return 1 }
        if let idx = arguments.firstIndex(of: "-derivedDataPath"), idx + 1 < arguments.count {
            let productsURL = URL(fileURLWithPath: arguments[idx + 1])
                .appendingPathComponent("Build/Products")
            try? FileManager.default.createDirectory(at: productsURL, withIntermediateDirectories: true)
            let plist: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: productsURL.appendingPathComponent("fake.xctestrun"))
        }
        return 0
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        (0, "")
    }
}

@Suite("MutantExecutor")
struct MutantExecutorTests {

    @Test("Given empty mutant list, when execute called, then returns empty results")
    func emptyMutantsReturnsEmpty() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeInput(projectPath: dir.path)

        let results = try await executor.execute(input)

        #expect(results.isEmpty)
    }

    @Test("Given build failure and schematizable mutants, when execute called, then fallback marks them unviable")
    func buildFailureMakesSchematizableMutantsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let mutant = makeMutant(id: "m0", filePath: sourceFile.path, isSchematizable: true)
        let input = makeInput(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .unviable)
    }

    @Test("Given incompatible mutant with nil content, when execute called, then returns unviable")
    func incompatibleMutantWithNilContentIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let mutant = makeMutant(id: "m0", filePath: "/tmp/Foo.swift", isSchematizable: false, mutatedContent: nil)
        let input = makeInput(projectPath: dir.path, mutants: [mutant])

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .unviable)
    }

    @Test("Given noCache is false and all mutants cached, when execute called, then returns from cache")
    func allCachedMutantsReturnFromCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheDir = URL(fileURLWithPath: dir.path).appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let mutant = makeMutant(id: "m0", filePath: "/tmp/Foo.swift", isSchematizable: true)
        let cacheKey = MutantCacheKey.make(for: mutant, testFilesHash: TestFilesHasher().hash(projectPath: dir.path))
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeInput(projectPath: dir.path, mutants: [mutant])

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .survived)
    }

    @Test("Given noCache is true, when execute called, then cache is not used")
    func noCacheTrueBypassesCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path, noCache: true),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeInput(projectPath: dir.path)

        let results = try await executor.execute(input)

        #expect(results.isEmpty)
    }

    @Test("Given quiet is false, when execute called, then reporter produces output")
    func nonQuietConfigurationProducesOutput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path, quiet: false),
            launcher: MockProcessLauncher(exitCode: 1)
        )

        let output = await captureOutput {
            _ = try? await executor.execute(makeInput(projectPath: dir.path))
        }

        #expect(output.contains("simulators ready"))
    }

    @Test("Given main build fails and fallback build succeeds, when execute called, then mutant is not marked unviable")
    func fallbackBuildSuccessExecutesTests() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path),
            launcher: FallbackBuildSucceedingMock()
        )
        let mutant = makeMutant(id: "m0", filePath: sourceFile.path, isSchematizable: true)
        let input = makeInput(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status != .unviable)
    }

    @Test("Given cached schematizable and uncached incompatible mutant, when execute called, then returns both")
    func fileLevelCacheHitReturnsCachedResultForSchematizableMutant() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let cacheDir = URL(fileURLWithPath: dir.path).appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let schematizableMutant = makeMutant(id: "m0", filePath: sourceFile.path, isSchematizable: true)
        let incompatibleMutant = makeMutant(
            id: "m1", filePath: "/tmp/Other.swift", isSchematizable: false, mutatedContent: nil)

        let testFilesHash = TestFilesHasher().hash(projectPath: dir.path)
        let cacheKey = MutantCacheKey.make(for: schematizableMutant, testFilesHash: testFilesHash)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let executor = MutantExecutor(
            configuration: makeConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeInput(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [schematizableMutant, incompatibleMutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 2)
        let schematizableResult = results.first { $0.descriptor.id == "m0" }
        let incompatibleResult = results.first { $0.descriptor.id == "m1" }
        #expect(schematizableResult?.status == .survived)
        #expect(incompatibleResult?.status == .unviable)
    }

    private func makeConfiguration(
        projectPath: String,
        noCache: Bool = false,
        quiet: Bool = true
    ) -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: projectPath,
            scheme: "MyScheme",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 1,
            noCache: noCache,
            quiet: quiet
        )
    }

    private func makeInput(
        projectPath: String,
        schematizedFiles: [SchematizedFile] = [],
        mutants: [MutantDescriptor] = []
    ) -> RunnerInput {
        RunnerInput(
            projectPath: projectPath,
            scheme: "MyScheme",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 1,
            noCache: false,
            schematizedFiles: schematizedFiles,
            supportFileContent: "",
            mutants: mutants
        )
    }

    private func makeMutant(
        id: String,
        filePath: String,
        isSchematizable: Bool,
        mutatedContent: String? = "let x = false"
    ) -> MutantDescriptor {
        MutantDescriptor(
            id: id,
            filePath: filePath,
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: isSchematizable,
            mutatedSourceContent: mutatedContent
        )
    }
}
