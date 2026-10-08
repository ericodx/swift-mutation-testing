import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor — Xcode attempts")
struct IncompatibleMutantXcodePathTests {
    static let original = "struct Config {\n    static let limit = 1 + 2\n}\n"
    static let mutated = "struct Config {\n    static let limit = 1 - 2\n}\n"
    static let offset =
        original.utf8.count - (original.range(of: "+ 2").map { original[$0.lowerBound...].utf8.count } ?? 0)

    @Test("Given a warm sandbox whose instrumented rebuild fails, when executed, then the plain mutant runs unmeasured")
    func aFailedInstrumentedRebuildRunsThePlainMutant() async throws {
        let (results, launcher) = try await execute(
            failsInstrumentedBuild: true, testRuns: [.passes(writesMarker: false)])

        #expect(results.map(\.status) == [.survived])
        #expect(results.map(\.activated) == [nil])
        #expect(await launcher.builtInstrumented == [false, true, false])
    }

    @Test("Given a test run that throws in a warm sandbox, when executed, then the error ends the pass")
    func aThrowingWarmRunEndsThePass() async throws {
        await #expect(throws: CocoaError.self) {
            _ = try await execute(testRuns: [.throwsError])
        }
    }

    @Test("Given a reproduction, when executed, then the instrumented copy is built and measured in its own sandbox")
    func aReproductionMeasuresTheInstrumentedCopy() async throws {
        let (results, launcher) = try await execute(reproducing: true, testRuns: [.passes(writesMarker: true)])

        #expect(results.map(\.status) == [.survived])
        #expect(results.map(\.activated) == [true])
        #expect(await launcher.builtInstrumented == [true])
    }

    @Test("Given a reproduction killed without activation, when executed, then its tests run again and decide")
    func aReproductionKillWithoutActivationIsRunAgain() async throws {
        let (results, launcher) = try await execute(
            reproducing: true, testRuns: [.fails("flaky()", writesMarker: false), .passes(writesMarker: false)]
        )

        #expect(results.map(\.status) == [.noCoverage])
        #expect(await launcher.testEnvironments.count == 2)
    }

    @Test("Given a reproduction whose test run throws, when executed, then the error ends it")
    func aThrowingReproductionEndsIt() async throws {
        await #expect(throws: CocoaError.self) {
            _ = try await execute(reproducing: true, testRuns: [.throwsError])
        }
    }

    @Test("Given a reproduction of a mutant with no content, when executed, then it is unviable without a build")
    func aReproductionWithoutContentIsUnviable() async throws {
        let (results, launcher) = try await execute(reproducing: true, content: nil, testRuns: [])

        #expect(results.map(\.status) == [.unviable])
        #expect(await launcher.builtInstrumented.isEmpty)
    }

    // MARK: - Private

    private func execute(
        reproducing: Bool = false,
        content: String? = mutated,
        failsInstrumentedBuild: Bool = false,
        testRuns: [ActivationScriptLauncher.TestRun]
    ) async throws -> ([ExecutionResult], ActivationScriptLauncher) {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let reproduction = reproducing ? Reproduction() : nil
        defer {
            for path in reproduction?.keptSandboxes ?? [] { try? FileManager.default.removeItem(atPath: path) }
            FileHelpers.cleanup(dir)
        }
        let sources = dir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("Config.swift")
        try Self.original.write(to: file, atomically: true, encoding: .utf8)

        let launcher = ActivationScriptLauncher(
            mutatedFile: "Sources/Config.swift", failsInstrumentedBuild: failsInstrumentedBuild, testRuns: testRuns
        )
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path),
            sandboxFactory: SandboxFactory()
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()
        var configuration = makeRunnerConfiguration(
            projectPath: dir.path, projectType: .xcode(scheme: "App", destination: "platform=macOS"), noCache: true
        )
        configuration.build.reproduction = reproduction

        let results = try await executor.execute(
            [
                makeMutantDescriptor(
                    filePath: file.path, line: 2, column: 26, utf8Offset: Self.offset, mutatedSourceContent: content
                )
            ],
            configuration: configuration,
            pool: pool
        )
        return (results, launcher)
    }
}
