import Foundation

struct RunConclusion: Sendable {
    let configuration: RunnerConfiguration
    let baseline: Baseline?

    func conclude(_ summary: RunnerSummary, identity: RunIdentity) throws -> ExitCode {
        TextReporter(projectRoot: configuration.projectPath).report(summary)
        Self.reportTiming(summary, configuration: configuration)
        let gate = Self.evaluateGate(summary, configuration: configuration, baseline: baseline)
        ReportWriter(configuration: configuration).write(summary, gate: gate, identity: identity)
        return try Self.applyGate(gate, summary: summary, configuration: configuration)
    }

    static func reportTiming(_ summary: RunnerSummary, configuration: RunnerConfiguration) {
        guard !summary.phases.isEmpty else { return }
        let reporter = TimingReporter()
        if configuration.reporting.timing {
            reporter.report(summary)
        }
        if let writer = MutantLogWriter(directory: configuration.reporting.keepLogsPath),
            let data = try? reporter.json(summary)
        {
            writer.write(timing: data)
        }
    }

    static func loadBaseline(for configuration: RunnerConfiguration) throws -> Baseline? {
        guard let path = configuration.gate.baselinePath else { return nil }

        let baseline = try BaselineStore().read(from: path)
        let differences = BaselineScope(configuration: configuration).differences(from: baseline.scope)

        guard differences.isEmpty else {
            throw GateError.scopeMismatch(path: path, differences: differences)
        }

        return baseline
    }

    static func evaluateGate(
        _ summary: RunnerSummary,
        configuration: RunnerConfiguration,
        baseline: Baseline?
    ) -> GateResult? {
        guard configuration.gate.isActive else { return nil }
        return QualityGate().evaluate(summary, policy: configuration.gate.policy, baseline: baseline)
    }

    static func applyGate(
        _ gate: GateResult?,
        summary: RunnerSummary,
        configuration: RunnerConfiguration,
        now: Date = Date()
    ) throws -> ExitCode {
        var exitCode = ExitCode.success

        if let gate {
            GateReporter(projectRoot: configuration.projectPath).report(gate)
            if !gate.passed {
                exitCode = .gateFailed
            }
        }

        if let path = configuration.gate.writeBaselinePath {
            let written = Baseline(
                summary: summary,
                scope: BaselineScope(configuration: configuration),
                projectPath: configuration.projectPath,
                toolVersion: Version.number,
                createdAt: now
            )
            try BaselineStore().write(written, to: path)
            StandardOutput.write("")
            StandardOutput.write("  ✓ Baseline: \(path)")
        }

        return exitCode
    }
}
