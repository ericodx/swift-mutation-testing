import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor — Xcode warm sandboxes")
struct IncompatibleMutantXcodeWarmTests {
    @Test("Given six mutants and room for two workers, when executed, then they share two sandboxes")
    func mutantsShareOneSandboxPerWorker() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))

        let results = try await run(mutants: 6, concurrency: 8, poolSize: 4, launcher: launcher, in: dir)

        let builds = await launcher.requests.filter { $0.arguments.first == "build-for-testing" }
        #expect(results.map(\.descriptor.id) == (0 ..< 6).map { "m\($0)" })
        #expect(Set(builds.map(\.workingDirectoryURL)).count == 2)
        #expect(builds.count > 2, "every mutant is rebuilt in its worker's sandbox")
        let tests = await launcher.requests.filter { $0.arguments.first == "test-without-building" }
        #expect(!tests.isEmpty)
        #expect(tests.allSatisfy { $0.arguments.contains("-collect-test-diagnostics") })
    }

    @Test("Given a project whose clean build fails, when executed, then every mutant is unviable with that output")
    func aFailedWarmBuildMakesEveryMutantUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(
            wrapping: MockProcessLauncher(exitCode: 0, responses: ["xcodebuild": (exitCode: 65, output: "boom")])
        )

        let results = try await run(mutants: 3, concurrency: 4, poolSize: 1, launcher: launcher, in: dir)

        let builds = await launcher.requests.filter { $0.arguments.first == "build-for-testing" }
        #expect(results.map(\.status) == [.unviable, .unviable, .unviable])
        #expect(builds.count == 1, "only the warm build ran")
    }

    @Test("Given a reproduction, when executed, then each mutant still gets a sandbox of its own, kept")
    func aReproductionKeepsOneSandboxPerMutant() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let reproduction = Reproduction()
        defer {
            for path in reproduction.keptSandboxes { try? FileManager.default.removeItem(atPath: path) }
            FileHelpers.cleanup(dir)
        }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))

        _ = try await run(
            mutants: 2, concurrency: 1, poolSize: 1, launcher: launcher, in: dir, reproduction: reproduction
        )

        #expect(Set(reproduction.keptSandboxes).count >= 2)
    }

    @Test("Given a mutated file outside the project, when executed, then it is unviable and the sandbox survives")
    func aFileOutsideTheProjectIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path),
            sandboxFactory: SandboxFactory()
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let results = try await executor.execute(
            [makeMutantDescriptor(filePath: "/elsewhere/Foo.swift", mutatedSourceContent: "let x = 1")],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.map(\.status) == [.unviable])
        #expect(await launcher.requests.filter { $0.arguments.first == "build-for-testing" }.count == 1)
    }

    @Test(
        "Given one worker warmed and the other failing to start, when executed, then the error ends it and frees both")
    func aWorkerFailingToWarmFreesTheOther() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = SecondWarmBuildThrows()
        let pool = SimulatorPool(baseUDID: nil, size: 2, destination: "platform=macOS", launcher: launcher)
        try await pool.setUp()
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path),
            sandboxFactory: SandboxFactory()
        )
        let file = dir.appendingPathComponent("Foo.swift")
        try "let x = 0".write(to: file, atomically: true, encoding: .utf8)
        let mutants = (0 ..< 2).map {
            makeMutantDescriptor(id: "m\($0)", filePath: file.path, mutatedSourceContent: "let x = \($0)")
        }

        await #expect(throws: CocoaError.self) {
            _ = try await executor.execute(
                mutants, configuration: makeRunnerConfiguration(projectPath: dir.path, concurrency: 8), pool: pool
            )
        }

        let first = try await pool.acquire()
        let second = try await pool.acquire()
        #expect([first, second].count == 2, "both slots went back to the pool")
    }

    // MARK: - Private

    private func run(
        mutants count: Int, concurrency: Int, poolSize: Int, launcher: any ProcessLaunching, in dir: URL,
        reproduction: Reproduction? = nil
    ) async throws -> [ExecutionResult] {
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path),
            sandboxFactory: SandboxFactory()
        )
        let pool = SimulatorPool(baseUDID: nil, size: poolSize, destination: "platform=macOS", launcher: launcher)
        try await pool.setUp()
        var configuration = makeRunnerConfiguration(projectPath: dir.path, concurrency: concurrency)
        configuration.build.reproduction = reproduction
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = 0".write(to: sourceFile, atomically: true, encoding: .utf8)
        let mutants = (0 ..< count).map {
            makeMutantDescriptor(
                id: "m\($0)", filePath: sourceFile.path, mutatedSourceContent: "let x = \($0)", fingerprint: "f\($0)"
            )
        }

        return try await executor.execute(mutants, configuration: configuration, pool: pool)
    }
}

private actor SecondWarmBuildThrows: ProcessLaunching {
    private var builds = 0

    func launch(
        executableURL: URL, arguments: [String], workingDirectoryURL: URL, timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String) {
        guard request.arguments.first == "build-for-testing" else { return (0, "") }
        builds += 1
        guard builds == 2 else { return (0, "") }
        try await Task.sleep(for: .milliseconds(300))
        throw CocoaError(.fileReadNoSuchFile)
    }
}
