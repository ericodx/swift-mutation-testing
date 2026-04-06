import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestExecutionStage")
struct TestExecutionStageTests {
    @Test("Given 3 mutants and concurrency of 1, when execute called, then all 3 results are returned")
    func executeReturnsAllResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let (stage, context) = makeTestExecutionFixture(in: dir, exitCode: 0)
        try await context.pool.setUp()

        let mutants = (0 ..< 3).map {
            makeMutantDescriptor(
                id: "m\($0)",
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                isSchematizable: true
            )
        }

        let results = try await stage.execute(mutants: mutants, in: context)

        #expect(results.count == 3)
    }

    @Test("Given mutant already in cache, when execute called again, then result reflects cached status")
    func cachedMutantReturnsCachedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeRunnerConfiguration()
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let successStage = TestExecutionStage(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 0),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
            )
        )
        _ = try await successStage.execute(mutants: [mutant], in: context)

        let failStage = TestExecutionStage(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
            )
        )
        let results = try await failStage.execute(mutants: [mutant], in: context)

        #expect(results.first?.status == .survived)
    }

    @Test("Given exit code 0, when mutant executed, then status is survived")
    func exitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let (stage, context) = makeTestExecutionFixture(in: dir, exitCode: 0)
        try await context.pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)

        #expect(results.first?.status == .survived)
    }

    @Test("Given noCache is true, when mutant executed, then cache is bypassed and result is fresh")
    func noCacheConfigurationBypassesCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let noCacheConfig = makeRunnerConfiguration(noCache: true)
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: noCacheConfig
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let survivedStage = TestExecutionStage(
            deps: makeExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 0),
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            )
        )
        _ = try await survivedStage.execute(mutants: [mutant], in: context)

        let killedStage = TestExecutionStage(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(
                    exitCode: 1,
                    output: "Test Case '-[S t]' failed (0.001 seconds)."
                ),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
            )
        )
        let results = try await killedStage.execute(mutants: [mutant], in: context)

        #expect(results.first?.status == .killed(by: "S.t"))
    }

    @Test("Given configuration with testTarget, when execute called, then testTarget is used in args")
    func configurationWithTestTargetExecutesSuccessfully() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = MockProcessLauncher(exitCode: 0)
        let pool = makeSimulatorPool(launcher: launcher)
        try await pool.setUp()
        let config = makeRunnerConfiguration(testTarget: "AppTests")
        let stage = TestExecutionStage(
            deps: makeExecutionDeps(
                launcher: launcher,
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            )
        )
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: config
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)
        #expect(results.count == 1)
    }

    @Test("Given exit code 1 with test failure in output, when mutant executed, then status is killed")
    func exitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let (stage, context) = makeTestExecutionFixture(in: dir, exitCode: 1, output: output)
        try await context.pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)

        #expect(results.first?.status == .killed(by: "MySuite.myTest"))
    }

    @Test("Given launcher throws during test execution, when execute called, then error is propagated")
    func launchThrowsPropagatesError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = MockProcessLauncher(exitCode: 0, throwsOnCapture: true)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let stage = TestExecutionStage(
            deps: makeExecutionDeps(
                launcher: launcher,
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            )
        )
        let context = TestExecutionContext(
            artifact: makeBuildArtifact(in: dir),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeRunnerConfiguration()
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        await #expect(throws: (any Error).self) {
            try await stage.execute(mutants: [mutant], in: context)
        }
    }

    @Test("Given SPM artifact and exit code 0, when execute called, then mutant survived")
    func spmExitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let (stage, context) = makeTestExecutionSPMFixture(in: dir, exitCode: 0)
        try await context.pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)

        #expect(results.first?.status == .survived)
    }

    @Test("Given SPM artifact and exit code 1 with failure output, when execute called, then mutant is killed")
    func spmExitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let (stage, context) = makeTestExecutionSPMFixture(in: dir, exitCode: 1, output: output)
        try await context.pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)

        #expect(results.first?.status == .killed(by: "myTest"))
    }

    @Test("Given SPM artifact with testTarget, when execute called, then returns result")
    func spmWithTestTargetReturnsResult() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let pool = makeSimulatorPool()
        try await pool.setUp()
        let config = makeRunnerConfiguration(projectType: .spm, testTarget: "MyLibTests")
        let stage = TestExecutionStage(
            deps: makeExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 0),
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            )
        )
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: nil),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: config
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)

        #expect(results.count == 1)
        #expect(results.first?.status == .survived)
    }

    @Test(
        "Given SPM launcher throws, when execute called, then pool slot is released and error propagated"
    )
    func spmLaunchThrowsReleasesSlotAndPropagates() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = MockProcessLauncher(exitCode: 0, throwsOnCapture: true)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let stage = TestExecutionStage(
            deps: makeExecutionDeps(
                launcher: launcher,
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            )
        )
        let config = makeRunnerConfiguration(projectType: .spm)
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: nil),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: config
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        await #expect(throws: (any Error).self) {
            try await stage.execute(mutants: [mutant], in: context)
        }
    }

    @Test("Given Xcode artifact with nil xctestrunURL, when execute called, then sandbox root is used as base")
    func xcodeNilXctestrunURLUsesSandboxRoot() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = MockProcessLauncher(exitCode: 0)
        let pool = makeSimulatorPool(launcher: launcher)
        try await pool.setUp()

        let plistDict: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))

        let stage = TestExecutionStage(
            deps: makeExecutionDeps(
                launcher: launcher,
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            )
        )
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: plist),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeRunnerConfiguration()
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            isSchematizable: true
        )

        let results = try await stage.execute(mutants: [mutant], in: context)

        #expect(results.count == 1)
    }
}
