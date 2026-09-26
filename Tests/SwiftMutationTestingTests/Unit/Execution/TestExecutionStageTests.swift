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
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")
            )
        )
        _ = try await successStage.execute(mutants: [mutant], in: context)

        let failStage = TestExecutionStage(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")
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
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")
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

    // MARK: - Timeouts under load

    private func makeLoadFixture(
        in dir: URL,
        launcher: TimeoutUnderLoadLauncher,
        reporter: MockProgressReporter
    ) async throws -> (TestExecutionStage, TestExecutionContext, ExecutionDeps) {
        let pool = SimulatorPool(baseUDID: nil, size: 4, destination: "platform=macOS", launcher: launcher)
        try await pool.setUp()
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path,
            reporter: reporter,
            total: 4
        )
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: nil),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeRunnerConfiguration(projectType: .spm, concurrency: 4)
        )
        return (TestExecutionStage(deps: deps), context, deps)
    }

    private func fourMutants() -> [MutantDescriptor] {
        (0 ..< 4).map { makeMutantDescriptor(id: "m\($0)", isSchematizable: true) }
    }

    @Test("Given a mutant that times out under load, when the pass ends, then it is run again alone and takes its real verdict")
    func timedOutMutantIsRetriedAloneAndTakesItsRealVerdict() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = TimeoutUnderLoadLauncher(timesOutFirst: ["m1"])
        let reporter = MockProgressReporter()
        let (stage, context, _) = try await makeLoadFixture(in: dir, launcher: launcher, reporter: reporter)

        let results = try await stage.execute(mutants: fourMutants(), in: context)

        #expect(results.count == 4)
        #expect(results.allSatisfy { $0.status == .survived })
        #expect(await launcher.attemptCount(for: "m1") == 2)
        #expect(await launcher.attemptCount(for: "m0") == 1)

        let finished = await reporter.events.filter {
            if case .mutantFinished = $0 { return true }
            return false
        }
        #expect(finished.count == 4)
    }

    @Test("Given a mutant that times out under load, when it is run again, then nothing else is running")
    func retryRunsAloneAfterEveryFirstAttempt() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = TimeoutUnderLoadLauncher(timesOutFirst: ["m0", "m2"])
        let (stage, context, _) = try await makeLoadFixture(in: dir, launcher: launcher, reporter: MockProgressReporter())

        _ = try await stage.execute(mutants: fourMutants(), in: context)

        let sequence = await launcher.sequence
        let lastFirstAttempt = sequence.lastIndex { $0.attempt == 1 } ?? -1
        let firstRetry = sequence.firstIndex { $0.attempt == 2 } ?? Int.max
        #expect(firstRetry > lastFirstAttempt)
        #expect(await launcher.maxInFlightDuringFirstAttempts >= 2)
        #expect(await launcher.inFlightDuringRetry == ["m0": 1, "m2": 1])
    }

    @Test("Given a mutant that times out even alone, when the pass ends, then it is reported as a timeout once")
    func mutantThatTimesOutAloneIsReportedAsTimeoutOnce() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = TimeoutUnderLoadLauncher(timesOutFirst: [], alwaysTimesOut: ["m3"])
        let reporter = MockProgressReporter()
        let (stage, context, _) = try await makeLoadFixture(in: dir, launcher: launcher, reporter: reporter)

        let results = try await stage.execute(mutants: fourMutants(), in: context)

        #expect(results.first { $0.descriptor.id == "m3" }?.status == .timeout)
        #expect(await launcher.attemptCount(for: "m3") == 2)

        let reportedForM3 = await reporter.events.filter {
            if case .mutantFinished(let descriptor, _, _, _) = $0 { return descriptor.id == "m3" }
            return false
        }
        #expect(reportedForM3.count == 1)
    }

    @Test("Given a cached mutant, when the pass runs, then it is neither run nor retried")
    func cachedMutantIsNotRetried() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = TimeoutUnderLoadLauncher(timesOutFirst: ["m0"])
        let (stage, context, deps) = try await makeLoadFixture(in: dir, launcher: launcher, reporter: MockProgressReporter())
        let mutants = fourMutants()
        await deps.cacheStore.store(status: .survived, for: MutantCacheKey.make(for: mutants[0]))

        let results = try await stage.execute(mutants: mutants, in: context)

        #expect(results.first { $0.descriptor.id == "m0" }?.status == .survived)
        #expect(await launcher.attemptCount(for: "m0") == 0)
    }
}
