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

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
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
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        _ = try await successStage.execute(mutants: [makeMutant(id: "m0")], in: context)

        let failStage = TestExecutionStage(
            launcher: MockProcessLauncher(exitCode: 1),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
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

    @Test("Given noCache is true, when mutant executed, then cache is bypassed and result is fresh")
    func noCacheConfigurationBypassesCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let noCacheConfig = RunnerConfiguration(
            projectPath: "/tmp",
            build: .init(
                projectType: .xcode(scheme: "S", destination: "platform=macOS"),
                timeout: 60, concurrency: 1, noCache: true),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: noCacheConfig,
            testFilesHash: "hash"
        )

        let survivedStage = TestExecutionStage(
            launcher: MockProcessLauncher(exitCode: 0),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        _ = try await survivedStage.execute(mutants: [makeMutant(id: "m0")], in: context)

        let killedStage = TestExecutionStage(
            launcher: MockProcessLauncher(
                exitCode: 1,
                output: "Test Case '-[S t]' failed (0.001 seconds)."
            ),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let results = try await killedStage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.first?.status == .killed(by: "S.t"))
    }

    @Test("Given configuration with testTarget, when execute called, then testTarget is used in args")
    func configurationWithTestTargetExecutesSuccessfully() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = MockProcessLauncher(exitCode: 0)
        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: launcher
        )
        try await pool.setUp()
        let config = RunnerConfiguration(
            projectPath: "/tmp",
            build: .init(
                projectType: .xcode(scheme: "S", destination: "platform=macOS"),
                testTarget: "AppTests", timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
        let stage = TestExecutionStage(
            launcher: launcher,
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: config,
            testFilesHash: "hash"
        )

        let results = try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)
        #expect(results.count == 1)
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

    @Test("Given launcher throws during test execution, when execute called, then error is propagated")
    func launchThrowsPropagatesError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = MockProcessLauncher(exitCode: 0, throwsOnCapture: true)
        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let stage = TestExecutionStage(
            launcher: launcher,
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeConfiguration(),
            testFilesHash: "hash"
        )

        await #expect(throws: (any Error).self) {
            try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)
        }
    }

    @Test("Given SPM artifact and exit code 0, when execute called, then mutant survived")
    func spmExitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let (stage, context) = makeSPMFixture(in: dir, exitCode: 0)
        try await context.pool.setUp()

        let results = try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.first?.status == .survived)
    }

    @Test("Given SPM artifact and exit code 1 with failure output, when execute called, then mutant is killed")
    func spmExitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let (stage, context) = makeSPMFixture(in: dir, exitCode: 1, output: output)
        try await context.pool.setUp()

        let results = try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.first?.status == .killed(by: "myTest"))
    }

    @Test("Given SPM artifact with testTarget, when execute called, then returns result")
    func spmWithTestTargetReturnsResult() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()
        let config = RunnerConfiguration(
            projectPath: "/tmp",
            build: .init(
                projectType: .spm, testTarget: "MyLibTests",
                timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
        let stage = TestExecutionStage(
            launcher: MockProcessLauncher(exitCode: 0),
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: nil),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: config,
            testFilesHash: "hash"
        )

        let results = try await stage.execute(mutants: [makeMutant(id: "m0")], in: context)

        #expect(results.count == 1)
        #expect(results.first?.status == .survived)
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
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 3)
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

    private func makeSPMFixture(
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
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let config = RunnerConfiguration(
            projectPath: "/tmp",
            build: .init(projectType: .spm, timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: nil),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: config,
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
            build: .init(
                projectType: .xcode(scheme: "MyScheme", destination: "platform=macOS"),
                timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
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
