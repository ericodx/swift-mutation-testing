import Testing

@testable import SwiftMutationTesting

@Suite("GateReporter")
struct GateReporterTests {
    private let reporter = GateReporter(projectRoot: "/p")

    @Test("Given a failed gate, when formatted, then each check shows its mark and the new mutants are listed")
    func formatsAFailedGate() {
        let result = GateResult(
            checks: [
                .newUndetected(count: 1, maximum: 0),
                .minScore(score: 90.44, minimum: 85),
                .scoreDrop(drop: 0.7, maximum: 2),
            ],
            newUndetected: [
                makeExecutionResult(
                    filePath: "/p/Sources/Parser.swift", line: 88, status: .survived,
                    operatorIdentifier: "RelationalOperatorReplacement"
                )
            ],
            fixedCount: 3
        )

        #expect(
            reporter.format(result) == """

                Quality gate: FAILED
                  ✗ 1 new undetected mutant (max 0)
                      Sources/Parser.swift:88   RelationalOperatorReplacement   + → -
                  ✓ score 90.4% ≥ 85.0%
                  ✓ score drop 0.7 pts ≤ 2.0 pts
                  ℹ 3 mutants detected now that were undetected in the baseline
                """
        )
    }

    @Test("Given failing score checks, when formatted, then the comparison is reversed")
    func formatsFailingScoreChecks() {
        let result = GateResult(
            checks: [.minScore(score: 60, minimum: 80), .scoreDrop(drop: 3, maximum: 2)],
            newUndetected: [],
            fixedCount: nil
        )

        let output = reporter.format(result)

        #expect(output.contains("Quality gate: FAILED"))
        #expect(output.contains("  ✗ score 60.0% < 80.0%"))
        #expect(output.contains("  ✗ score drop 3.0 pts > 2.0 pts"))
    }

    @Test("Given a score that rose, when formatted, then it says the score did not drop")
    func formatsAScoreThatRose() {
        let result = GateResult(checks: [.scoreDrop(drop: -1.5, maximum: 0)], newUndetected: [], fixedCount: 0)

        #expect(reporter.format(result).contains("  ✓ score did not drop (max drop 0.0 pts)"))
    }

    @Test("Given score checks without a score, when formatted, then they fail and say there is no score")
    func formatsScoreChecksWithoutAScore() {
        let result = GateResult(
            checks: [.minScore(score: nil, minimum: 80), .scoreDrop(drop: nil, maximum: 2)],
            newUndetected: [],
            fixedCount: nil
        )

        let output = reporter.format(result)

        #expect(output.contains("Quality gate: FAILED"))
        #expect(output.contains("  ✗ no score, since no mutant could be tested (min 80.0%)"))
        #expect(output.contains("  ✗ no score to compare with the baseline's (max drop 2.0 pts)"))
    }

    @Test("Given more new mutants than the limit, when formatted, then the rest are summarized")
    func truncatesTheList() {
        let results = (1 ... GateReporter.listedLimit + 5).map {
            makeExecutionResult(filePath: "/p/A.swift", line: $0, status: .survived)
        }
        let result = GateResult(
            checks: [.newUndetected(count: results.count, maximum: 0)], newUndetected: results, fixedCount: 0
        )

        let lines = reporter.format(result).components(separatedBy: "\n")

        #expect(lines.filter { $0.hasPrefix("      A.swift:") }.count == GateReporter.listedLimit)
        #expect(lines.last == "      and 5 more — see the report")
    }

    @Test("Given new mutants without a maximum, when formatted, then they are reported as information")
    func reportsNewMutantsWithoutAMaximum() {
        let result = GateResult(
            checks: [],
            newUndetected: [
                makeExecutionResult(status: .survived), makeExecutionResult(status: .survived),
            ],
            fixedCount: 1
        )

        let output = reporter.format(result)

        #expect(output.contains("Quality gate: PASSED"))
        #expect(output.contains("  ℹ 2 new undetected mutants since the baseline"))
        #expect(output.contains("  ℹ 1 mutant detected now that were undetected in the baseline"))
    }

    @Test("Given an integrity warning check, when formatted, then it counts the warnings against the maximum")
    func formatsTheIntegrityWarningCheck() {
        let result = GateResult(
            checks: [.integrityWarnings(count: 2, maximum: 0), .integrityWarnings(count: 1, maximum: 1)],
            newUndetected: [],
            fixedCount: nil
        )

        let output = reporter.format(result)

        #expect(output.contains("  ✗ 2 integrity warnings (max 0)"))
        #expect(output.contains("  ✓ 1 integrity warning (max 1)"))
    }
}
