import Foundation
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

    @Test("Given build failure and schematizable mutants, when execute called, then fallback marks them unviable")
    func buildFailureMakesSchematizableMutantsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
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
            mutatedSourceContent: "let x = false"
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

    @Test("Given incompatible mutant with nil content, when execute called, then returns unviable")
    func incompatibleMutantWithNilContentIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: false,
            mutatedSourceContent: nil
        )
        let input = makeRunnerInput(projectPath: dir.path, mutants: [mutant])

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

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false"
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

        #expect(output.contains("simulators ready"))
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: nil
        )

        let cacheKey = MutantCacheKey.make(for: schematizableMutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
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
            mutatedSourceContent: "let x = false"
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
            launcher: MockProcessLauncher(exitCode: 1)
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: "let y = false"
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: "let y = false"
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
            mutatedSourceContent: nil
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
            mutatedSourceContent: nil
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
            mutatedSourceContent: nil
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: "let x = false"
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
            mutatedSourceContent: "let y = false"
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
            mutatedSourceContent: "let x = false"
        )
        let cacheKey = MutantCacheKey.make(for: mutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .killed(by: "SomeTest"), for: cacheKey, killerTestFile: "Tests/SomeTest.swift")
        try await cacheStore.persist()

        let metadata = CacheStore.CacheMetadata(testFileHashes: [:])
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
            mutatedSourceContent: "let x = false"
        )
        let cacheKey = MutantCacheKey.make(for: mutant)
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: cacheKey)
        try await cacheStore.persist()

        let metadata = CacheStore.CacheMetadata(testFileHashes: ["Tests/FooTests.swift": "old-hash"])
        try await cacheStore.persistMetadata(metadata)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: MockProcessLauncher(exitCode: 1)
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
            mutatedSourceContent: "let x = false"
        )
        let mutantB = makeMutantDescriptor(
            id: "m1",
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let y = false"
        )
        let cacheStore = CacheStore(storePath: cacheDir.appendingPathComponent("results.json").path)
        await cacheStore.store(status: .survived, for: MutantCacheKey.make(for: mutantA))
        await cacheStore.store(status: .killed(by: "T"), for: MutantCacheKey.make(for: mutantB))
        try await cacheStore.persist()

        let metadata = CacheStore.CacheMetadata(testFileHashes: [:])
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
            mutatedSourceContent: "let x = false"
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
}
