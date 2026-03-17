import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("PerFileBuildFallback")
struct PerFileBuildFallbackTests {
    @Test("Given 3 mutants across 2 files, when builds fail, then 3 unviable results are returned in file order")
    func executeReturnsMutantsForAllFilesInOrder() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fallback = makeFallback(in: dir, exitCode: 1)
        let pool = makePool()
        try await pool.setUp()

        let input = makeInput(
            projectPath: dir.path,
            files: ["/tmp/FileA.swift", "/tmp/FileB.swift"],
            mutants: [
                makeMutant(id: "m0", filePath: "/tmp/FileA.swift"),
                makeMutant(id: "m1", filePath: "/tmp/FileA.swift"),
                makeMutant(id: "m2", filePath: "/tmp/FileB.swift"),
            ]
        )

        let results = try await fallback.execute(
            input: input,
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.count == 3)
        #expect(results.map(\.descriptor.id) == ["m0", "m1", "m2"])
    }

    @Test("Given build failure, when execute called, then all file mutants are unviable")
    func buildFailureMarksAllFileMutantsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fallback = makeFallback(in: dir, exitCode: 1)
        let pool = makePool()
        try await pool.setUp()

        let input = makeInput(
            projectPath: dir.path,
            files: ["/tmp/Foo.swift"],
            mutants: [
                makeMutant(id: "m0", filePath: "/tmp/Foo.swift"),
                makeMutant(id: "m1", filePath: "/tmp/Foo.swift"),
            ]
        )

        let results = try await fallback.execute(
            input: input,
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .unviable })
    }

    @Test("Given all mutants cached, when execute called again with invalid path, then cached results returned")
    func allMutantsCachedSkipsBuild() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makePool()
        try await pool.setUp()

        let mutant = makeMutant(id: "m0", filePath: "/tmp/Foo.swift")

        let firstFallback = PerFileBuildFallback(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter()
        )
        _ = try await firstFallback.execute(
            input: makeInput(projectPath: dir.path, files: ["/tmp/Foo.swift"], mutants: [mutant]),
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        let secondFallback = PerFileBuildFallback(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter()
        )
        let results = try await secondFallback.execute(
            input: makeInput(projectPath: "/non/existent/path", files: ["/tmp/Foo.swift"], mutants: [mutant]),
            configuration: makeConfiguration(projectPath: "/non/existent/path"),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given non-schematizable mutants in input, when execute called, then they are excluded from results")
    func nonSchematizableMutantsAreExcluded() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fallback = makeFallback(in: dir, exitCode: 1)
        let pool = makePool()
        try await pool.setUp()

        let input = makeInput(
            projectPath: dir.path,
            files: ["/tmp/Foo.swift"],
            mutants: [
                makeMutant(id: "m0", filePath: "/tmp/Foo.swift", isSchematizable: true),
                makeMutant(id: "m1", filePath: "/tmp/Foo.swift", isSchematizable: false),
            ]
        )

        let results = try await fallback.execute(
            input: input,
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.count == 1)
        #expect(results.first?.descriptor.id == "m0")
    }

    private func makeFallback(in dir: URL, exitCode: Int32) -> PerFileBuildFallback {
        PerFileBuildFallback(
            launcher: MockProcessLauncher(exitCode: exitCode),
            sandboxFactory: SandboxFactory(),
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter()
        )
    }

    private func makePool() -> SimulatorPool {
        SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
    }

    private func makeConfiguration(projectPath: String, noCache: Bool = false) -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: projectPath,
            scheme: "MyScheme",
            destination: "platform=macOS",
            testTarget: nil,
            timeout: 60,
            concurrency: 1,
            noCache: noCache,
            output: nil,
            htmlOutput: nil,
            sonarOutput: nil,
            quiet: true
        )
    }

    private func makeInput(projectPath: String, files: [String], mutants: [MutantDescriptor]) -> RunnerInput {
        RunnerInput(
            projectPath: projectPath,
            scheme: "MyScheme",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 1,
            noCache: false,
            schematizedFiles: files.map { SchematizedFile(originalPath: $0, schematizedContent: "let x = 0") },
            supportFileContent: "",
            mutants: mutants
        )
    }

    private func makeMutant(id: String, filePath: String, isSchematizable: Bool = true) -> MutantDescriptor {
        MutantDescriptor(
            id: id,
            filePath: filePath,
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            replacementKind: .binaryOperator,
            description: "Replace + with -",
            isSchematizable: isSchematizable,
            mutatedSourceContent: nil
        )
    }
}
