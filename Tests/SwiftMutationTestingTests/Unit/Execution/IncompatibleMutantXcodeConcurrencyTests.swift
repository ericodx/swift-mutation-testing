import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor — Xcode concurrency")
struct IncompatibleMutantXcodeConcurrencyTests {
    @Test(
        "Given a concurrency, a pool and some mutants, when the width is worked out, then the smallest bound wins",
        arguments: [(8, 4, 10, 2), (16, 2, 10, 2), (16, 8, 3, 3), (2, 4, 10, 1), (8, 4, 0, 1)]
    )
    func theWidthIsTheSmallestBound(concurrency: Int, poolSize: Int, mutants: Int, expected: Int) {
        #expect(
            IncompatibleMutantExecutor.xcodeWidth(concurrency: concurrency, poolSize: poolSize, mutantCount: mutants)
                == expected
        )
    }

    @Test("Given six mutants and room for two, when executed, then two build at once and results keep their order")
    func mutantsBuildTwoAtATimeInOrder() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = BuildConcurrencyProbe()
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path),
            sandboxFactory: SandboxFactory()
        )
        let pool = SimulatorPool(baseUDID: nil, size: 4, destination: "platform=macOS", launcher: launcher)
        try await pool.setUp()
        let mutants = (0 ..< 6).map {
            makeMutantDescriptor(id: "m\($0)", mutatedSourceContent: "let x = \($0)", fingerprint: "f\($0)")
        }

        let results = try await executor.execute(
            mutants, configuration: makeRunnerConfiguration(projectPath: dir.path, concurrency: 8), pool: pool
        )

        #expect(results.map(\.descriptor.id) == (0 ..< 6).map { "m\($0)" })
        #expect(await launcher.mostAtOnce == 2)
    }
}

private actor BuildConcurrencyProbe: ProcessLaunching {
    private var inFlight = 0
    private(set) var mostAtOnce = 0

    func launch(
        executableURL: URL, arguments: [String], workingDirectoryURL: URL, timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String) {
        guard request.arguments.contains("build-for-testing") else { return (0, "") }
        inFlight += 1
        mostAtOnce = max(mostAtOnce, inFlight)
        try await Task.sleep(for: .milliseconds(100))
        inFlight -= 1
        return (0, "")
    }
}
