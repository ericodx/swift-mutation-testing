import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestExecutionStage")
struct TestExecutionStageTests {
    @Test("Given 3 mutants and concurrency of 1, when execute called, then all 3 results are returned")
    func executeReturnsAllResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let (stage, context) = makeFixture(in: dir, exitCode: 0)
        try await context.pool.setUp()

        let mutants = (0 ..< 3).map { makeMutant(id: "m\($0)") }

        let results = try await stage.execute(mutants: mutants, in: context)

        #expect(results.count == 3)
    }

    @Test("Given mutant already in cache, when execute called again, then result reflects cached status")
    func cachedMutantReturnsCachedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(cacheURL: dir.appendingPathComponent("cache.json"))
        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeConfiguration(),
            testFilesHash: "hash"
        )

        let successStage = TestExecutionStage(
            launcher: MockProcessLauncher(exitCode: 0),
            cacheStore: cacheStore,
            reporter: MockProgressReporter()
        )
        _ = try await successStage.execute(mutants: [makeMutant(id: "m0")], in: context)

        let failStage = TestExecutionStage(
            launcher: MockProcessLauncher(exitCode: 1),
            cacheStore: cacheStore,
            reporter: MockProgressReporter()
        )
        let results = try await failStage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.first?.status == .survived)
    }

    @Test("Given exit code 0, when mutant executed, then status is survived")
    func exitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let (stage, context) = makeFixture(in: dir, exitCode: 0)
        try await context.pool.setUp()

        let results = try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.first?.status == .survived)
    }

    @Test("Given exit code 1 with test failure in output, when mutant executed, then status is killed")
    func exitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let (stage, context) = makeFixture(in: dir, exitCode: 1, output: output)
        try await context.pool.setUp()

        let results = try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.first?.status == .killed(by: "MySuite.myTest"))
    }

    private func makeFixture(
        in dir: URL,
        exitCode: Int32,
        output: String = ""
    ) -> (TestExecutionStage, TestExecutionContext) {
        let launcher = MockProcessLauncher(exitCode: exitCode, output: output)
        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: launcher
        )
        let stage = TestExecutionStage(
            launcher: launcher,
            cacheStore: CacheStore(cacheURL: dir.appendingPathComponent("cache.json")),
            reporter: MockProgressReporter()
        )
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeConfiguration(),
            testFilesHash: "hash"
        )
        return (stage, context)
    }

    private func makeBuildArtifact(in dir: URL) -> BuildArtifact {
        let plistDict: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
        let data = try! PropertyListSerialization.data(
            fromPropertyList: plistDict, format: .xml, options: 0
        )
        let plist = XCTestRunPlist(data)!
        return BuildArtifact(derivedDataPath: dir.path, xctestrunURL: dir, plist: plist)
    }

    private func makeConfiguration() -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: "/tmp",
            scheme: "MyScheme",
            destination: "platform=macOS",
            testTarget: nil,
            timeout: 60,
            concurrency: 1,
            noCache: false,
            output: nil,
            htmlOutput: nil,
            sonarOutput: nil,
            quiet: true
        )
    }

    private func makeMutant(id: String) -> MutantDescriptor {
        MutantDescriptor(
            id: id,
            filePath: "/tmp/Foo.swift",
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            replacementKind: .binaryOperator,
            description: "Replace + with -",
            isSchematizable: true,
            mutatedSourceContent: nil
        )
    }
}
