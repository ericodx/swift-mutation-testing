import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MarkdownReporter")
struct MarkdownReporterTests {
    private let reporter = MarkdownReporter(outputPath: "/unused", projectRoot: "/p")

    @Test("Given a run without a gate, when formatted, then it shows the score, the files and the undetected mutants")
    func formatsARunWithoutAGate() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/p/Sources/B.swift", line: 3, status: .killed(by: "t"), activated: true
                ),
                makeExecutionResult(
                    id: "2", filePath: "/p/Sources/B.swift", line: 9, status: .timeout, activated: true
                ),
                makeExecutionResult(
                    id: "3", filePath: "/p/Sources/A.swift", line: 4, status: .survived, activated: true
                ),
                makeExecutionResult(
                    id: "4", filePath: "/p/Sources/A.swift", line: 2, status: .noCoverage, activated: false
                ),
                makeExecutionResult(id: "5", filePath: "/p/Sources/A.swift", line: 1, status: .unviable),
            ],
            totalDuration: 0
        )

        #expect(
            reporter.format(summary) == """
                ## Mutation testing

                **Mutation score: 50.0%**

                Detected: 2 (killed 1, timeout 1) / Undetected: 2 (survived 1, no coverage 1)

                Killed: 1 · Survived: 1 · Timeouts: 1 · Unviable: 1 · No coverage: 1

                ### Results by file

                | File | Score | Killed | Survived | Timeout | Unviable | No coverage |
                |---|---:|---:|---:|---:|---:|---:|
                | Sources/A.swift | 0.0% | 0 | 1 | 0 | 1 | 1 |
                | Sources/B.swift | 100.0% | 1 | 0 | 1 | 0 | 0 |

                ### Undetected mutants

                | Location | Operator | Mutation | Status |
                |---|---|---|---|
                | Sources/A.swift:2 | ArithmeticOperatorReplacement | `+ → -` | no coverage |
                | Sources/A.swift:4 | ArithmeticOperatorReplacement | `+ → -` | survived |

                """
        )
    }

    @Test("Given a failed gate, when formatted, then its checks and new undetected mutants follow the totals")
    func formatsAFailedGate() {
        let survivor = makeExecutionResult(filePath: "/p/Sources/A.swift", line: 4, status: .survived)
        let gate = GateResult(
            checks: [.newUndetected(count: 1, maximum: 0), .minScore(score: 0, minimum: 80)],
            newUndetected: [survivor],
            fixedCount: 2
        )

        let output = reporter.format(RunnerSummary(results: [survivor], totalDuration: 0), gate: gate)

        #expect(
            output.contains(
                """
                ### Quality gate: failed ❌

                - ✗ 1 new undetected mutant (max 0)
                - ✗ score 0.0% < 80.0%
                - ℹ 2 mutants detected now that were undetected in the baseline

                New undetected mutants:

                | Location | Operator | Mutation | Status |
                |---|---|---|---|
                | Sources/A.swift:4 | ArithmeticOperatorReplacement | `+ → -` | survived |
                """
            )
        )
    }

    @Test("Given a passed gate with new mutants but no maximum, when formatted, then they are counted")
    func formatsAPassedGateWithNewMutants() {
        let survivor = makeExecutionResult(status: .survived)
        let gate = GateResult(checks: [], newUndetected: [survivor], fixedCount: 0)

        let output = reporter.format(RunnerSummary(results: [survivor], totalDuration: 0), gate: gate)

        #expect(output.contains("### Quality gate: passed ✅"))
        #expect(output.contains("- ℹ 1 new undetected mutant since the baseline"))
        #expect(!output.contains("detected now that were undetected"))
    }

    @Test("Given one integrity warning, when formatted, then the count is singular")
    func oneIntegrityWarningIsSingular() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(status: .killed(by: "flaky"), activated: false)], totalDuration: 0
        )

        #expect(reporter.format(summary).contains("⚠️ Integrity warnings: 1 mutant killed or timed out"))
    }

    @Test("Given a failed integrity warning check, when formatted, then the gate lists it")
    func formatsTheIntegrityWarningCheck() {
        let warning = makeExecutionResult(status: .killed(by: "flaky"), activated: false)
        let gate = GateResult(checks: [.integrityWarnings(count: 1, maximum: 0)], newUndetected: [], fixedCount: nil)

        let output = reporter.format(RunnerSummary(results: [warning], totalDuration: 0), gate: gate)

        #expect(output.contains("### Quality gate: failed ❌\n\n- ✗ 1 integrity warning (max 0)"))
    }

    @Test("Given more undetected mutants than the limit, when formatted, then the table stops at the limit")
    func truncatesTheUndetectedTable() {
        let results = (1 ... MarkdownReporter.listedLimit + 3).map {
            makeExecutionResult(id: "\($0)", filePath: "/p/A.swift", line: $0, status: .survived)
        }

        let lines = reporter.format(RunnerSummary(results: results, totalDuration: 0)).components(separatedBy: "\n")

        #expect(lines.contains("### Undetected mutants (first 20 of 23)"))
        #expect(lines.filter { $0.hasPrefix("| A.swift:") }.count == MarkdownReporter.listedLimit)
        #expect(lines.contains("…and 3 more — see the full report."))
    }

    @Test("Given a mutation with pipes and backticks, when formatted, then the table cell stays intact")
    func escapesTableCells() {
        let result = ExecutionResult(
            descriptor: makeMutantDescriptor(filePath: "/p/A.swift", description: "a || `b` → a && `b`"),
            status: .survived,
            testDuration: 0
        )

        let output = reporter.format(RunnerSummary(results: [result], totalDuration: 0))

        #expect(output.contains("| `a \\|\\| 'b' → a && 'b'` |"))
    }

    @Test("Given an empty run, when formatted, then there is no file or mutant table")
    func omitsEmptyTables() {
        let output = reporter.format(RunnerSummary(results: [], totalDuration: 0))

        #expect(output.contains("**Mutation score: 100.0%**"))
        #expect(!output.contains("### Results by file"))
        #expect(!output.contains("### Undetected mutants"))
    }

    @Test("Given a summary, when reported, then the file holds the formatted Markdown")
    func writesTheFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("summary.md").path
        let summary = RunnerSummary(results: [makeExecutionResult(status: .survived)], totalDuration: 0)
        let reporter = MarkdownReporter(outputPath: path, projectRoot: "/tmp")

        try reporter.report(summary)

        #expect(try String(contentsOfFile: path, encoding: .utf8) == reporter.format(summary))
    }
}
