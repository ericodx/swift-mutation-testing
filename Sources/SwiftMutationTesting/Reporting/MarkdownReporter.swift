import Foundation

struct MarkdownReporter: Sendable {
    static let listedLimit = 20

    let outputPath: String
    let projectRoot: String

    func report(_ summary: RunnerSummary, gate: GateResult? = nil) throws {
        try format(summary, gate: gate).write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
    }

    func format(_ summary: RunnerSummary, gate: GateResult? = nil) -> String {
        var lines = ["## Mutation testing", ""]
        lines.append("**Mutation score: \(summary.formattedScore)**")
        lines.append("")
        lines.append(summary.detectionLine)
        lines.append("")
        lines.append(
            "Killed: \(summary.killed.count) · Survived: \(summary.survived.count)"
                + " · Timeouts: \(summary.timeouts.count) · Unviable: \(summary.unviable.count)"
                + " · No coverage: \(summary.noCoverage.count)"
        )

        if !summary.integrityWarnings.isEmpty {
            let count = summary.integrityWarnings.count
            lines.append("")
            lines.append(
                "⚠️ Integrity warnings: \(count) mutant\(count == 1 ? "" : "s")"
                    + " killed or timed out without the mutated code running"
            )
        }
        if !summary.unconfirmedKills.isEmpty {
            let count = summary.unconfirmedKills.count
            lines.append("")
            lines.append(
                "Kills not repeated alone: \(count) mutant\(count == 1 ? "" : "s")"
                    + " killed only while other workers ran, judged by a run on their own"
            )
        }
        if !summary.activationNotMeasured.isEmpty {
            lines.append("")
            lines.append("Activation not measured: \(GateResult.count(summary.activationNotMeasured.count, "mutant"))")
        }
        if let cacheLine = summary.cacheLine {
            lines.append("")
            lines.append(cacheLine)
        }

        if let gate {
            lines.append(contentsOf: gateSection(gate))
        }

        lines.append(contentsOf: filesSection(summary))
        lines.append(contentsOf: undetectedSection(summary))

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private

    private func gateSection(_ gate: GateResult) -> [String] {
        var lines = ["", "### Quality gate: \(gate.passed ? "passed ✅" : "failed ❌")", ""]
        lines.append(contentsOf: gate.checks.map { "- \($0.passed ? "✓" : "✗") \($0.summary)" })
        lines.append(contentsOf: gate.notes.map { "- ℹ \($0)" })
        if !gate.newUndetected.isEmpty {
            lines.append("")
            lines.append("New undetected mutants:")
            lines.append("")
            lines.append(contentsOf: mutantTable(gate.newUndetected))
        }
        return lines
    }

    private func filesSection(_ summary: RunnerSummary) -> [String] {
        guard !summary.results.isEmpty else { return [] }
        var lines = [
            "", "### Results by file", "",
            "| File | Score | Killed | Survived | Timeout | Unviable | No coverage |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ]
        for (filePath, file) in summary.files {
            lines.append(
                "| \(cell(relative(filePath))) | \(file.formattedScore)"
                    + " | \(file.killed.count) | \(file.survived.count) | \(file.timeouts.count)"
                    + " | \(file.unviable.count) | \(file.noCoverage.count) |"
            )
        }
        return lines
    }

    private func undetectedSection(_ summary: RunnerSummary) -> [String] {
        let undetected = RunnerSummary.byLocation(summary.undetected)
        guard !undetected.isEmpty else { return [] }
        let heading =
            undetected.count > Self.listedLimit
            ? "### Undetected mutants (first \(Self.listedLimit) of \(undetected.count))"
            : "### Undetected mutants"
        return ["", heading, ""] + mutantTable(undetected)
    }

    private func mutantTable(_ results: [ExecutionResult]) -> [String] {
        var lines = ["| Location | Operator | Mutation | Status |", "|---|---|---|---|"]
        for result in RunnerSummary.byLocation(results).prefix(Self.listedLimit) {
            let descriptor = result.descriptor
            let status = result.status == .noCoverage ? "no coverage" : "survived"
            lines.append(
                "| \(cell(relative(descriptor.filePath))):\(descriptor.line) | \(descriptor.operatorIdentifier)"
                    + " | \(code(descriptor.description)) | \(status) |"
            )
        }
        if results.count > Self.listedLimit {
            lines.append("")
            lines.append("…and \(results.count - Self.listedLimit) more — see the full report.")
        }
        return lines
    }

    private func relative(_ path: String) -> String {
        ProjectRelativePath.make(for: path, in: projectRoot)
    }

    private func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    private func code(_ text: String) -> String {
        "`\(cell(text).replacingOccurrences(of: "`", with: "'"))`"
    }
}
