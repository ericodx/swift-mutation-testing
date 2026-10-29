import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor — mutants dealt from a queue")
struct IncompatibleMutantQueueTests {
    @Test("Given one warm build slow and one quick, when executed, then the quick one starts before the slow one ends")
    func theQuickSandboxStartsWhileTheSlowOneStillBuilds() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "let x = 1".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        let launcher = WarmSandboxLauncher(laterWarmBuildsWaitForTheFirstTest: true)

        let results = try await execute(fourIncompatibleMutants(in: dir), launcher: launcher, in: dir)

        #expect(results.allSatisfy { $0.status == .survived })
        #expect(await launcher.testRunsByRoot.values.reduce(0, +) == 4)
        let firstTest = try #require(await launcher.firstTestStartedAt)
        let slowBuildEnd = try #require(await launcher.warmBuildsFinishedAt.max())
        #expect(firstTest < slowBuildEnd, "the slow build was still running when the first mutant started")
    }

    @Test("Given a sandbox whose test runs are slow, when executed, then the other one takes the rest of the queue")
    func aSlowSandboxTakesFewerMutants() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "let x = 1".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        let launcher = WarmSandboxLauncher(
            laterWarmBuildsWaitForTheFirstTest: true, testRunsTake: [.milliseconds(300), .zero]
        )

        let results = try await execute(fourIncompatibleMutants(in: dir), launcher: launcher, in: dir)

        #expect(results.map(\.descriptor.id) == ["m0", "m1", "m2", "m3"])
        #expect(await launcher.testRunsByRoot.values.sorted() == [1, 3])
    }

    @Test("Given one warm build slow and one quick, when timed, then the warm phase ends as the quick one is ready")
    func theWarmPhaseEndsWhenTheFirstSandboxIsReady() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "let x = 1".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        let launcher = WarmSandboxLauncher(
            laterWarmBuildsWaitForTheFirstTest: true, testRunsTake: [.milliseconds(50)]
        )
        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: launcher)

        _ = try await execute(fourIncompatibleMutants(in: dir), launcher: launcher, in: dir, executor: executor)

        let entries = await executor.deps.timings.entries
        let warm = try #require(entries.first { $0.phase == .warmSandboxes })
        let incompatible = try #require(entries.first { $0.phase == .incompatible })
        let quickBuildEnd = try #require(await launcher.warmBuildsFinishedAt.min())
        let slowBuildEnd = try #require(await launcher.warmBuildsFinishedAt.max())
        let warmEnd = warm.start.addingTimeInterval(warm.duration)
        #expect(abs(warmEnd.timeIntervalSince(quickBuildEnd)) < 0.1, "the warm phase ends with the quick sandbox")
        #expect(warmEnd < slowBuildEnd)
        #expect(abs(incompatible.start.timeIntervalSince(warmEnd)) < 0.01)
        #expect(incompatible.start.addingTimeInterval(incompatible.duration) >= slowBuildEnd, "the slow build overlaps")
    }

    @Test("Given every warm build fails, when timed, then only the warm phase is recorded")
    func noIncompatiblePhaseWhenNothingBuilt() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "let x = 1".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        let launcher = WarmSandboxLauncher(failsEveryBuild: true)
        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: launcher)

        let results = try await execute(
            fourIncompatibleMutants(in: dir), launcher: launcher, in: dir, executor: executor
        )

        #expect(results.map(\.status) == [.unviable, .unviable, .unviable, .unviable])
        #expect(await executor.deps.timings.entries.map(\.phase) == [.warmSandboxes])
    }

    @Test("Given a content-less mutant between two viable ones, when executed, then results keep the input order")
    func resultsKeepTheInputOrderAroundAContentLessMutant() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let file = dir.appendingPathComponent("Foo.swift")
        try "let x = 1".write(to: file, atomically: true, encoding: .utf8)
        let mutants = [
            makeMutantDescriptor(id: "m0", filePath: file.path, mutatedSourceContent: "let x = 10"),
            makeMutantDescriptor(id: "m1", filePath: file.path, mutatedSourceContent: nil),
            makeMutantDescriptor(id: "m2", filePath: file.path, mutatedSourceContent: "let x = 12"),
        ]

        let results = try await execute(mutants, launcher: WarmSandboxLauncher(), in: dir)

        #expect(results.map(\.descriptor.id) == ["m0", "m1", "m2"])
        #expect(results.map(\.status) == [.survived, .unviable, .survived])
    }

    // MARK: - Private

    private func execute(
        _ mutants: [MutantDescriptor], launcher: WarmSandboxLauncher, in dir: URL,
        executor: IncompatibleMutantExecutor? = nil
    ) async throws -> [ExecutionResult] {
        let executor = executor ?? makeIncompatibleMutantExecutorSPM(in: dir, launcher: launcher)
        let pool = makeSimulatorPool()
        try await pool.setUp()
        return try await executor.execute(
            mutants,
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, concurrency: 8),
            pool: pool
        )
    }

    private func fourIncompatibleMutants(in dir: URL) -> [MutantDescriptor] {
        (0 ..< 4).map {
            makeMutantDescriptor(
                id: "m\($0)",
                filePath: dir.appendingPathComponent("Foo.swift").path,
                utf8Offset: $0,
                mutatedSourceContent: "let x = \($0 + 10)",
                sourceContentHash: "test-hash",
                fingerprint: "fingerprint"
            )
        }
    }
}
