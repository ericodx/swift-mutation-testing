import Foundation
import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor")
struct MutantExecutorTests {
    @Test("Given empty mutant list, when execute called, then returns empty results")
    func emptyMutantsReturnsEmpty() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeRunnerInput(projectPath: dir.path)

        let results = try await executor.execute(input)

        #expect(results.isEmpty)
    }

    @Test("Given a reporter in the environment, when execute called, then the run's progress goes to it")
    func progressGoesToTheReporterGiven() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let reporter = MockProgressReporter()

        let results = try await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1)),
            environment: MutantExecutor.Environment(reporter: reporter)
        ).execute(
            makeRunnerInput(
                projectPath: dir.path,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
                mutants: [
                    makeMutantDescriptor(
                        id: "m0", filePath: sourceFile.path, originalText: "true", mutatedText: "false",
                        isSchematizable: true, sourceContentHash: "test-hash"
                    )
                ]
            )
        )

        let events = await reporter.events
        #expect(results.count == 1)
        #expect(events.contains { if case .buildStarted = $0 { true } else { false } })
        #expect(events.contains { if case .mutantFinished = $0 { true } else { false } })
    }

    @Test("Given build failure and schematizable mutants, when execute called, then fallback marks them unviable")
    func buildFailureMakesSchematizableMutantsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1))
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .unviable)
    }

    @Test("Given incompatible mutant with nil content, when execute called, then the run stops before any build")
    func incompatibleMutantWithNilContentStopsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: launcher
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: false,
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(projectPath: dir.path, mutants: [mutant])

        await #expect(throws: IntegrityError.mutantsNotApplied(mutants: ["m0 (Foo.swift:1)"])) {
            try await executor.execute(input)
        }
        #expect(await launcher.requests.isEmpty)
    }

    @Test("Given noCache is false and all mutants cached, when execute called, then returns from cache")
    func allCachedMutantsReturnFromCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheDir = URL(fileURLWithPath: dir.path).appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let cacheKey = MutantCacheKey.make(for: mutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeRunnerInput(projectPath: dir.path, mutants: [mutant])

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .survived)
    }

    @Test("Given noCache is true, when execute called, then cache is not used")
    func noCacheTrueBypassesCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, noCache: true),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeRunnerInput(projectPath: dir.path)

        let results = try await executor.execute(input)

        #expect(results.isEmpty)
    }

    @Test("Given keep-logs, when a mutant is tested, then its captured output is written")
    func keepLogsWritesPerMutantOutput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let logs = dir.appendingPathComponent("logs")

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, projectType: .spm, keepLogsPath: logs.path
            ),
            launcher: MockProcessLauncher(exitCode: 0, output: "Test Suite 'All tests' passed")
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        _ = try await executor.execute(input)

        let log = try String(contentsOf: logs.appendingPathComponent("m0.log"), encoding: .utf8)
        #expect(log.contains("BooleanLiteralReplacement"))
        #expect(log.contains("Test Suite 'All tests' passed"))
    }

    @Test("Given no keep-logs, when a mutant is tested, then no log directory is created")
    func withoutKeepLogsNothingIsWritten() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: MockProcessLauncher(exitCode: 0)
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [
                makeMutantDescriptor(
                    id: "m0", filePath: sourceFile.path, isSchematizable: true,
                    mutatedSourceContent: "let x = false", sourceContentHash: "test-hash"
                )
            ]
        )

        _ = try await executor.execute(input)

        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!entries.contains("logs"))
    }

    @Test("Given quiet is false, when execute called, then reporter produces output")
    func nonQuietConfigurationProducesOutput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, quiet: false),
            launcher: MockProcessLauncher(exitCode: 1)
        )

        let output = await captureOutput {
            _ = try? await executor.execute(makeRunnerInput(projectPath: dir.path))
        }

        #expect(output.contains("worker ready"))
    }

    @Test("Given main build fails and fallback build succeeds, when execute called, then mutant is not marked unviable")
    func fallbackBuildSuccessExecutesTests() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: FallbackBuildSucceedingMock()
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
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

        let schematizableMutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let incompatibleMutant = makeMutantDescriptor(
            id: "m1",
            filePath: "/tmp/Other.swift",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: false,
            mutatedSourceContent: "let y = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )

        let cacheKey = MutantCacheKey.make(for: schematizableMutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1))
        )
        let input = makeRunnerInput(
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

    @Test("Given SPM project type and schematizable mutants with exit code 0, when execute called, then survived")
    func spmSchematizableMutantsSurviveOnExitCodeZero() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: MockProcessLauncher(exitCode: 0)
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .survived)
    }

    @Test("Given SPM project type and build failure, when execute called, then mutant is marked unviable")
    func spmBuildFailureMarksSchematizableMutantsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1))
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .unviable)
    }

    @Test("Given SPM build fails with canonical path in error, when retry succeeds, then only failing file is unviable")
    func spmRetryExcludingErrorsMatchesCanonicalPaths() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        let barFile = dir.appendingPathComponent("Bar.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)
        try "let y = true".write(to: barFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMRetryExcludingErrorsMock()
        )
        let mutantFoo = makeMutantDescriptor(
            id: "m0",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let mutantBar = makeMutantDescriptor(
            id: "m1",
            filePath: barFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let y = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false"),
                SchematizedFile(originalPath: barFile.path, schematizedContent: "let y = false"),
            ],
            mutants: [mutantFoo, mutantBar]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 2)
        let fooResult = results.first { $0.descriptor.id == "m0" }
        let barResult = results.first { $0.descriptor.id == "m1" }
        #expect(fooResult?.status == .survived)
        #expect(barResult?.status == .survived)
    }

    @Test("Given SPM build fails on one file, when the schema is retried, then the console says which mutants left it")
    func spmRetryIsReported() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        let barFile = dir.appendingPathComponent("Bar.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)
        try "let y = true".write(to: barFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, quiet: false),
            launcher: SPMRetryExcludingErrorsMock()
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false"),
                SchematizedFile(originalPath: barFile.path, schematizedContent: "let y = false"),
            ],
            mutants: [
                makeMutantDescriptor(
                    id: "m0", filePath: fooFile.path, isSchematizable: true, mutatedSourceContent: "let x = false"
                ),
                makeMutantDescriptor(
                    id: "m1", filePath: barFile.path, isSchematizable: true, mutatedSourceContent: "let y = false"
                ),
            ]
        )

        let output = await captureOutput {
            _ = try? await executor.execute(input)
        }

        #expect(output.contains("  ⚠ Schema did not build: retrying without 1 mutant, to be built on its own"))
        #expect(output.contains("  ✓ Built in"))
    }

    @Test("Given SPM build error on line inside first case block, when retry, then only that mutant is excluded")
    func spmNarrowExclusionOnSpecificCase() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        try "let original = true".write(to: fooFile, atomically: true, encoding: .utf8)

        let schematized =
            "func foo() {\n"
            + "switch __swiftMutationTestingID {\n"
            + "case \"swift-mutation-testing_0\":\n"
            + "return true\n"
            + "case \"swift-mutation-testing_1\":\n"
            + "return false\n"
            + "default:\n"
            + "return nil\n"
            + "}\n"
            + "}"

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMNarrowExclusionMock()
        )
        let mutantFoo = makeMutantDescriptor(
            id: "swift-mutation-testing_0",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let mutantBar = makeMutantDescriptor(
            id: "swift-mutation-testing_1",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let y = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: schematized)
            ],
            mutants: [mutantFoo, mutantBar]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 2)
        let resultFirst = results.first { $0.descriptor.id == "swift-mutation-testing_0" }
        let resultSecond = results.first { $0.descriptor.id == "swift-mutation-testing_1" }
        #expect(resultFirst?.status == .survived)
        #expect(resultSecond?.status == .survived)
    }

    @Test("Given excluded mutants with same file, when rewrite attempted, then source is cached for second mutant")
    func excludedMutantsFromSameFileUsesSourceCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMRetryExcludingErrorsMock()
        )

        let mutantA = makeMutantDescriptor(
            id: "swift-mutation-testing_0",
            filePath: fooFile.path,
            column: 9,
            utf8Offset: 8,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )

        let mutantB = makeMutantDescriptor(
            id: "swift-mutation-testing_1",
            filePath: fooFile.path,
            column: 9,
            utf8Offset: 8,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false")],
            mutants: [mutantA, mutantB]
        )

        let results = try await executor.execute(input)
        #expect(results.count == 2)
    }

    @Test("Given excluded mutant with mismatched offset, when rewrite attempted, then marked unviable")
    func excludedMutantWithMismatchedOffsetIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMRetryExcludingErrorsMock()
        )

        let badMutant = makeMutantDescriptor(
            id: "swift-mutation-testing_0",
            filePath: fooFile.path,
            utf8Offset: 9999,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false")],
            mutants: [badMutant]
        )

        let results = try await executor.execute(input)
        #expect(results.count == 1)
        #expect(results.first?.status == .unviable)
    }

    @Test("Given SPM project type with testTarget, when execute called, then testTarget is used in baseline validation")
    func spmWithTestTargetAppliesFilter() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let config = makeRunnerConfiguration(
            projectPath: dir.path,
            projectType: .spm,
            testTarget: "FooTests"
        )

        let executor = MutantExecutor(
            configuration: config,
            launcher: MockProcessLauncher(exitCode: 0)
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )
        let results = try await executor.execute(input)
        #expect(results.count == 1)
    }

    @Test("Given SPM build fails twice with error paths, when retry recurses, then second retry excludes more mutants")
    func spmRecursiveRetryExcludesAdditionalMutants() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        let barFile = dir.appendingPathComponent("Bar.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)
        try "let y = true".write(to: barFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMDoubleFailMock()
        )
        let mutantFoo = makeMutantDescriptor(
            id: "swift-mutation-testing_0",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let mutantBar = makeMutantDescriptor(
            id: "swift-mutation-testing_1",
            filePath: barFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let y = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false"),
                SchematizedFile(originalPath: barFile.path, schematizedContent: "let y = false"),
            ],
            mutants: [mutantFoo, mutantBar]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 2)
    }

    @Test(
        "Given all mutants cached and no test files changed, when execute called, then returns from cache without building"
    )
    func allCachedWithUnchangedTestFilesReturnsCachedResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheDir = URL(fileURLWithPath: dir.path).appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let cacheKey = MutantCacheKey.make(for: mutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .killed(by: "SomeTest"), for: cacheKey, killerTestFile: "Tests/SomeTest.swift")
        try await cacheStore.persist()

        let metadata = CacheStore.CacheMetadata(
            testFileHashes: [:], testSelection: CacheTestSelection(makeRunnerConfiguration(projectPath: dir.path).build)
        )
        try await cacheStore.persistMetadata(metadata)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeRunnerInput(projectPath: dir.path, mutants: [mutant])

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .killed(by: "SomeTest"))
        #expect(results[0].killerTestFile == "Tests/SomeTest.swift")
    }

    @Test(
        "Given cached survived mutant and test file changed, when execute called, then invalidation removes entry and falls through"
    )
    func invalidationRemovesSurvivedEntryWhenTestFileChanged() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let cacheDir = URL(fileURLWithPath: dir.path).appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let cacheKey = MutantCacheKey.make(for: mutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let metadata = CacheStore.CacheMetadata(
            testFileHashes: ["Tests/FooTests.swift": "old-hash"],
            testSelection: CacheTestSelection(makeRunnerConfiguration(projectPath: dir.path).build)
        )
        try await cacheStore.persistMetadata(metadata)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1))
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .unviable)
    }

    @Test("Given all mutants cached, when execute called with quiet false, then reporter shows loaded from cache count")
    func allCachedReportsCorrectCount() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheDir = URL(fileURLWithPath: dir.path).appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let mutantA = makeMutantDescriptor(
            id: "m0",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let mutantB = makeMutantDescriptor(
            id: "m1",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let y = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: MutantCacheKey.make(for: mutantA))
        await cacheStore.store(status: .killed(by: "T"), for: MutantCacheKey.make(for: mutantB))
        try await cacheStore.persist()

        let metadata = CacheStore.CacheMetadata(
            testFileHashes: [:], testSelection: CacheTestSelection(makeRunnerConfiguration(projectPath: dir.path).build)
        )
        try await cacheStore.persistMetadata(metadata)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, quiet: false),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let input = makeRunnerInput(projectPath: dir.path, mutants: [mutantA, mutantB])

        let output = await captureOutput {
            _ = try? await executor.execute(input)
        }

        #expect(output.contains("Loaded 2 mutants from cache"))
    }

    @Test(
        "Given excluded mutant whose source file disappears before rewrite, when execute called, then marked unviable")
    func excludedMutantWithMissingSourceIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)

        let config = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)
        let executor = MutantExecutor(
            configuration: config,
            launcher: SPMRetryWithFileDeletionMock(fileToDelete: fooFile.path)
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false",
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .unviable)
    }

    @Test("Given an Xcode project, when execute called, then the shared build is bounded by the build timeout")
    func xcodeSharedBuildUsesBuildTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, timeout: 30, buildTimeout: 240
            ),
            launcher: launcher
        )

        _ = try? await executor.execute(
            makeRunnerInput(
                projectPath: dir.path,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        #expect(await launcher.timeouts(forCommandStartingWith: "build-for-testing") == [240])
    }

    @Test("Given an SPM project, when execute called, then every shared build is bounded by the build timeout")
    func spmSharedBuildUsesBuildTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, projectType: .spm, timeout: 30, buildTimeout: 240
            ),
            launcher: launcher
        )

        _ = try await executor.execute(
            makeRunnerInput(
                projectPath: dir.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        let buildTimeouts = await launcher.timeouts(forCommandStartingWith: "build")
        let testTimeouts = await launcher.timeouts(forCommandStartingWith: "test")

        #expect(!buildTimeouts.isEmpty)
        #expect(buildTimeouts.allSatisfy { $0 == 240 })
        #expect(!testTimeouts.isEmpty)
        #expect(testTimeouts.allSatisfy { $0 <= 30 * TestExecutionStage.loadedTimeoutFactor })
    }

    @Test("Given the shared build times out, when execute called, then the run fails instead of reporting unviable")
    func sharedBuildTimeoutEndsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: MockProcessLauncher(exitCode: SPMResultParser.timedOutExitCode)
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
        )

        await #expect(throws: BuildError.timedOut(seconds: 0, output: "")) {
            try await executor.execute(input)
        }
    }

    @Test("Given the shared build times out, when the run fails, then its sandbox is removed")
    func aFailedRunLeavesNoSandboxBehind() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let marker = "Marker-\(UUID().uuidString).swift"
        let sourceFile = dir.appendingPathComponent(marker)
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: MockProcessLauncher(exitCode: SPMResultParser.timedOutExitCode)
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
        )

        await #expect(throws: BuildError.self) {
            try await executor.execute(input)
        }

        let sandboxDirectory = SandboxName.directory
        let holdsMarker: (String) -> Bool = { name in
            let path = sandboxDirectory.appending(path: "\(name)/\(marker)").path
            return FileManager.default.fileExists(atPath: path)
        }
        let sandboxes = try FileManager.default.contentsOfDirectory(atPath: sandboxDirectory.path)
            .filter { $0.hasPrefix(SandboxName.prefix) && holdsMarker($0) }
        #expect(sandboxes.isEmpty)
    }

    @Test("Given the first SPM build fails, when the retry build runs, then it is also bounded by the build timeout")
    func spmRetryBuildUsesBuildTimeout() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = RecordingSPMRetryLauncher(failingFileName: "Foo.swift")
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, projectType: .spm, timeout: 30, buildTimeout: 240
            ),
            launcher: launcher
        )

        _ = try? await executor.execute(
            makeRunnerInput(
                projectPath: dir.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        let buildTimeouts = await launcher.timeouts(forCommandStartingWith: "build")
        #expect(buildTimeouts.count >= 2)
        #expect(buildTimeouts.allSatisfy { $0 == 240 })
    }

    // MARK: - Build output formats

    @Test(
        "Given the build reports errors with the path after the error label, when the retry runs, then only the failing file is excluded",
        arguments: ["error: ", "\u{1B}[1;31merror: \u{1B}[1;39m"]
    )
    func retryReadsErrorsWithThePathAfterTheLabel(prefix: String) async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        let barFile = dir.appendingPathComponent("Bar.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)
        try "let y = true".write(to: barFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, quiet: false),
            launcher: SPMRetrySwiftBuildFormatMock(prefix: prefix)
        )
        let mutantFoo = makeMutantDescriptor(
            id: "m0", filePath: fooFile.path, originalText: "true", mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement", replacementKind: .booleanLiteral,
            description: "true → false", isSchematizable: true,
            mutatedSourceContent: "let x = false", sourceContentHash: "hash"
        )
        let mutantBar = makeMutantDescriptor(
            id: "m1", filePath: barFile.path, originalText: "true", mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement", replacementKind: .booleanLiteral,
            description: "true → false", isSchematizable: true,
            mutatedSourceContent: "let y = false", sourceContentHash: "hash"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false"),
                SchematizedFile(originalPath: barFile.path, schematizedContent: "let y = false"),
            ],
            mutants: [mutantFoo, mutantBar]
        )

        var results: [ExecutionResult] = []
        let output = await captureOutput {
            results = (try? await executor.execute(input)) ?? []
        }

        #expect(results.count == 2)
        #expect(output.contains("Built in"))
    }

    // MARK: - Testing libraries

    @Test(
        "Given a bundle with no XCTest tests, when mutants run, then the XCTest pass is probed once and skipped for every mutant"
    )
    func emptyXCTestLibraryIsSkippedAfterOneProbe() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = EmptyXCTestBundleLauncher()
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        )
        let mutants = (0 ..< 3).map {
            makeMutantDescriptor(id: "m\($0)", filePath: sourceFile.path, utf8Offset: $0, isSchematizable: true)
        }
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: mutants
        )

        let results = try await executor.execute(input)

        #expect(results.map(\.status) == [.survived, .survived, .survived])
        #expect((await launcher.xctestRuns, await launcher.swiftTestingRuns) == (1, 4))
    }

    @Test("Given no library reports tests, when the probe ends, then mutants are still run against both")
    func aProbeThatFindsNothingKeepsBothLibraries() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = EmptyBundleLauncher()
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
        )

        let results = try await executor.execute(input)

        #expect(results.map(\.status) == [.survived])
        #expect((await launcher.xctestRuns, await launcher.swiftTestingRuns) == (2, 2))
    }

    @Test("Given the first library passes, when the second fails, then the verdict names the second's test")
    func aFailureInTheSecondLibraryNamesItsTest() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = TwoLibraryBundleLauncher(
            xctestOutput: "Test Case '-[CalculatorTests testAddition]' failed (0.002 seconds).",
            xctestExitCode: 1,
            swiftTestingOutput: "✔ Test run with 3 tests in 1 suite passed after 0.1 seconds.",
            probePasses: true
        )
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: dir.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        #expect(results.map(\.status) == [.killed(by: "CalculatorTests.testAddition")])
    }

    @Test("Given the first library uses up the timeout, when the second would run, then the mutant times out")
    func aLibraryThatUsesUpTheTimeoutStopsTheNextOne() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let launcher = TwoLibraryBundleLauncher(
            xctestOutput: "Test Suite 'All tests' passed\nExecuted 3 tests, with 0 failures",
            swiftTestingOutput: "✔ Test run with 3 tests passed",
            swiftTestingDelay: .milliseconds(400),
            probePasses: true
        )
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, projectType: .spm, timeout: 0.1
            ),
            launcher: launcher
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: dir.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        #expect(results.map(\.status) == [.timeout])
    }

    // MARK: - Targeted tests first

    private func targetedProject(in dir: URL, withSuite: Bool) throws -> URL {
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let tests = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let name = withSuite ? "FooTests" : "OtherTests"
        try "@Suite struct \(name) {}".write(
            to: tests.appendingPathComponent("\(name).swift"), atomically: true, encoding: .utf8
        )
        return sourceFile
    }

    private func targetedInput(projectDir dir: URL, sourceFile: URL) -> RunnerInput {
        makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
        )
    }

    @Test("Given the file's own suite kills the mutant, when executed, then the full suite never runs")
    func aKillInTheTargetedSuiteEndsTheRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = try targetedProject(in: dir, withSuite: true)

        let launcher = TargetedRunLauncher(
            targetedOutcome: (1, #"✘ Test "a check" failed after 0.001 seconds with 1 issue."#)
        )
        let results = try await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        ).execute(targetedInput(projectDir: dir, sourceFile: sourceFile))

        #expect(results.map(\.status) == [.killed(by: "a check")])
        #expect(await launcher.filters == ["FooTests"])
    }

    @Test("Given the file's own suite lets the mutant live, when executed, then the full suite decides")
    func aSurvivorOfTheTargetedSuiteGoesToTheFullSuite() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = try targetedProject(in: dir, withSuite: true)

        let launcher = TargetedRunLauncher(
            targetedOutcome: (0, "✔ Test run with 2 tests in 1 suite passed after 0.1 seconds."),
            fullOutcome: (1, #"✘ Test "elsewhere" failed after 0.001 seconds with 1 issue."#)
        )
        let results = try await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        ).execute(targetedInput(projectDir: dir, sourceFile: sourceFile))

        #expect(results.map(\.status) == [.killed(by: "elsewhere")])
        #expect(await launcher.filters == ["FooTests", nil])
    }

    @Test("Given no suite named after the file, when executed, then only the full suite runs")
    func aFileWithoutItsOwnSuiteRunsTheFullSuiteOnly() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = try targetedProject(in: dir, withSuite: false)

        let launcher = TargetedRunLauncher(targetedOutcome: (1, "should never be asked"))
        let results = try await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        ).execute(targetedInput(projectDir: dir, sourceFile: sourceFile))

        #expect(results.map(\.status) == [.survived])
        #expect(await launcher.filters == [nil])
    }

    @Test("Given a workspace container, when the shared build runs, then xcodebuild is given the workspace")
    func theSharedBuildUsesTheContainer() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        var configuration = makeRunnerConfiguration(projectPath: dir.path)
        configuration.build.xcodeContainer = .workspace("Apps/App.xcworkspace")
        let launcher = RecordingProcessLauncher(responses: [(0, "")])

        _ = try? await MutantExecutor(configuration: configuration, launcher: launcher).execute(
            makeRunnerInput(
                projectPath: dir.path,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        let build = try #require(await launcher.recorded(commandStartingWith: "build-for-testing"))
        #expect(build.arguments.suffix(2) == ["-workspace", "Apps/App.xcworkspace"])
    }
}
