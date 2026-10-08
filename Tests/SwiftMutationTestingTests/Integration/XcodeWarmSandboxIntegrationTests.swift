import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite(.tags(.integration), .serialized, .notInsideAMutationRun)
struct XcodeWarmSandboxIntegrationTests {
    @Test("Given mutants of two files in one warm sandbox, when run in turn, then none inherits the one before")
    func consecutiveMutantsDoNotLeakIntoEachOther() async throws {
        let fixture = try FixtureCopy.make("CalcApp")
        defer { fixture.remove() }
        let calculator = fixture.url.appending(path: "Sources/Calculator.swift").path
        let validator = fixture.url.appending(path: "Sources/Validator.swift").path
        let original = try String(contentsOfFile: calculator, encoding: .utf8)
        let validatorOriginal = try String(contentsOfFile: validator, encoding: .utf8)
        let mutants = [
            mutant("w0", in: calculator, original: original, replacing: "a + b", with: "a - b"),
            mutant("w1", in: validator, original: validatorOriginal, replacing: "value <= 100", with: "value < 100"),
            mutant("w2", in: calculator, original: original, replacing: "a - b", with: "a + b"),
        ]
        let launcher = CountingLauncher(wrapping: XcodeProcessLauncher())
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(
                launcher: launcher, cacheStorePath: fixture.url.appending(path: "cache.json").path, total: 3
            ),
            sandboxFactory: SandboxFactory()
        )
        let pool = SimulatorPool(baseUDID: nil, size: 1, destination: "platform=macOS", launcher: launcher)
        try await pool.setUp()

        let results = try await executor.execute(
            mutants,
            configuration: RunnerConfiguration(
                projectPath: fixture.url.path,
                build: .init(
                    projectType: .xcode(scheme: "CalcApp", destination: "platform=macOS"),
                    timeout: 60, buildTimeout: 120, concurrency: 1, noCache: true
                ),
                reporting: .init(quiet: true),
                filter: .init(excludePatterns: [], operators: [])
            ),
            pool: pool
        )

        #expect(results.map(\.descriptor.id) == ["w0", "w1", "w2"])
        #expect(results[0].status.isKill)
        #expect(results[1].status == .survived)
        #expect(results[2].status.isKill)
        let builds = await launcher.requests.filter { $0.arguments.first == "build-for-testing" }
        #expect(Set(builds.map(\.workingDirectoryURL)).count == 1, "every build ran in the one warm sandbox")
        #expect(try String(contentsOfFile: calculator, encoding: .utf8) == original)
        #expect(try String(contentsOfFile: validator, encoding: .utf8) == validatorOriginal)
    }

    private func mutant(
        _ id: String, in path: String, original: String, replacing old: String, with new: String
    ) -> MutantDescriptor {
        let offset = original.utf8.count - (original.range(of: old).map { original[$0.lowerBound...].utf8.count } ?? 0)
        return makeMutantDescriptor(
            id: id, filePath: path, utf8Offset: offset, originalText: old, mutatedText: new,
            mutatedSourceContent: original.replacingOccurrences(of: old, with: new), fingerprint: id
        )
    }
}
