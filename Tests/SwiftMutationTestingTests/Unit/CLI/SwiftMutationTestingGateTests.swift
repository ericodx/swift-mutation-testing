import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SwiftMutationTesting quality gate", .serialized)
struct SwiftMutationTestingGateTests {
    @Test("Given no gate settings, when the gate is applied, then the run succeeds and prints nothing")
    func inactiveGateSucceedsSilently() {
        var exitCode: ExitCode?
        let output = captureOutputSync {
            exitCode = try? apply(configuration())
        }

        #expect(exitCode == .success)
        #expect(output.isEmpty)
    }

    @Test("Given a gate that fails, when applied, then the run exits with the gate code and reports why")
    func failedGateExitsWithTheGateCode() {
        var exitCode: ExitCode?
        let output = captureOutputSync {
            exitCode = try? apply(configuration(policy: GatePolicy(minScore: 90)))
        }

        #expect(exitCode == .gateFailed)
        #expect(ExitCode.gateFailed.rawValue == 2)
        #expect(output.contains("Quality gate: FAILED"))
    }

    @Test("Given a gate that passes, when applied, then the run succeeds and reports it")
    func passedGateSucceeds() {
        var exitCode: ExitCode?
        let output = captureOutputSync {
            exitCode = try? apply(configuration(policy: GatePolicy(minScore: 50)))
        }

        #expect(exitCode == .success)
        #expect(output.contains("Quality gate: PASSED"))
    }

    @Test("Given a failing gate and a baseline to write, when applied, then the baseline is still written")
    func writesTheBaselineEvenWhenTheGateFails() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("next.json").path
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        var exitCode: ExitCode?
        let output = captureOutputSync {
            exitCode = try? apply(
                configuration(projectPath: dir.path, policy: GatePolicy(minScore: 90), write: path),
                now: now
            )
        }

        let written = try BaselineStore().read(from: path)
        #expect(exitCode == .gateFailed)
        #expect(output.contains("  ✓ Baseline: \(path)"))
        #expect(written.createdAt == now)
        #expect(written.toolVersion == Version.number)
        #expect(written.undetected.map(\.fingerprint) == ["survived"])
    }

    @Test("Given a baseline whose scope matches, when loaded, then it is returned")
    func loadsAMatchingBaseline() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("b.json").path
        try BaselineStore().write(makeBaseline(undetected: ["x"]), to: path)

        let baseline = try RunConclusion.loadBaseline(for: configuration(projectPath: dir.path, baseline: path))

        #expect(baseline?.undetected.map(\.fingerprint) == ["x"])
    }

    @Test("Given no baseline configured, when loaded, then there is none")
    func loadsNothingWithoutABaseline() throws {
        #expect(try RunConclusion.loadBaseline(for: configuration()) == nil)
    }

    @Test("Given a baseline recorded with other operators, when loaded, then the scope mismatch is an error")
    func rejectsABaselineWithAnotherScope() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("b.json").path
        let scope = BaselineScope(operators: ["NegateConditional"], sourcesPath: ".", excludePatterns: [])
        try BaselineStore().write(makeBaseline(scope: scope), to: path)

        #expect {
            try RunConclusion.loadBaseline(for: configuration(projectPath: dir.path, baseline: path))
        } throws: { error in
            guard case .scopeMismatch(_, let differences) = error as? GateError else { return false }
            return differences.count == 1 && differences[0].hasPrefix("operators:")
        }
    }

    @Test("Given a baseline with another scope, when run, then it stops with an error before any mutant runs")
    func runStopsOnAScopeMismatch() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "scheme: App\ndestination: platform=macOS\n".write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8
        )
        let scope = BaselineScope(operators: ["NegateConditional"], sourcesPath: ".", excludePatterns: [])
        try BaselineStore().write(makeBaseline(scope: scope), to: dir.appendingPathComponent("b.json").path)
        let launcher = RecordingProcessLauncher(responses: [(exitCode: 0, output: "")])

        let result = await SwiftMutationTesting.run(args: [dir.path, "--baseline", "b.json"], launcher: launcher)

        #expect(result == .error)
        #expect(await launcher.requests.isEmpty)
    }

    @Test("Given a minimum score a project with every mutant killed meets, when run, then it succeeds")
    func runPassesTheGate() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "scheme: App\ndestination: platform=macOS\nmin-score: 100\n".write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8
        )
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )

        let result = await SwiftMutationTesting.run(args: [dir.path], launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1)))

        #expect(result == .success)
    }

    private func apply(_ configuration: RunnerConfiguration, now: Date = Date()) throws -> ExitCode {
        let gate = RunConclusion.evaluateGate(summary(), configuration: configuration, baseline: nil)
        return try RunConclusion.applyGate(gate, summary: summary(), configuration: configuration, now: now)
    }

    private func summary() -> RunnerSummary {
        RunnerSummary(
            results: [
                makeExecutionResult(status: .killed(by: "t"), fingerprint: "killed"),
                makeExecutionResult(filePath: "/tmp/Foo.swift", status: .survived, fingerprint: "survived"),
            ],
            totalDuration: 0
        )
    }

    private func configuration(
        projectPath: String = "/tmp",
        policy: GatePolicy = GatePolicy(),
        baseline: String? = nil,
        write: String? = nil
    ) -> RunnerConfiguration {
        var configuration = makeRunnerConfiguration(projectPath: projectPath)
        configuration.gate = .init(policy: policy, baselinePath: baseline, writeBaselinePath: write)
        return configuration
    }
}
