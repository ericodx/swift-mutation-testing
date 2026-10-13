import Testing

@testable import SwiftMutationTesting

@Suite("QualityGate")
struct QualityGateTests {
    private let gate = QualityGate()

    @Test("Given a score at the minimum, when evaluated, then the gate passes")
    func scoreAtTheMinimumPasses() {
        let result = gate.evaluate(summary(killed: 3, survived: ["a"]), policy: GatePolicy(minScore: 75), baseline: nil)

        #expect(result.checks == [.minScore(score: 75, minimum: 75)])
        #expect(result.passed)
    }

    @Test("Given a score below the minimum, when evaluated, then the gate fails")
    func scoreBelowTheMinimumFails() {
        let result = gate.evaluate(summary(killed: 1, survived: ["a"]), policy: GatePolicy(minScore: 75), baseline: nil)

        #expect(!result.passed)
    }

    @Test("Given a drop within the maximum, when evaluated, then the gate passes")
    func dropWithinTheMaximumPasses() {
        let result = gate.evaluate(
            summary(killed: 3, survived: ["a"]),
            policy: GatePolicy(maxScoreDrop: 5),
            baseline: makeBaseline(score: 80, undetected: ["a"])
        )

        #expect(result.checks == [.scoreDrop(drop: 5, maximum: 5)])
        #expect(result.passed)
    }

    @Test("Given a drop above the maximum, when evaluated, then the gate fails")
    func dropAboveTheMaximumFails() {
        let result = gate.evaluate(
            summary(killed: 1, survived: ["a"]),
            policy: GatePolicy(maxScoreDrop: 5),
            baseline: makeBaseline(score: 80, undetected: ["a"])
        )

        #expect(!result.passed)
    }

    @Test("Given undetected mutants all in the baseline, when evaluated, then none is new and the gate passes")
    func knownUndetectedMutantsAreNotNew() {
        let result = gate.evaluate(
            summary(killed: 1, survived: ["a", "b"]),
            policy: GatePolicy(maxNewSurvivors: 0),
            baseline: makeBaseline(undetected: ["a", "b"])
        )

        #expect(result.newUndetected.isEmpty)
        #expect(result.passed)
    }

    @Test("Given a survivor missing from the baseline, when evaluated with a maximum of 0, then the gate fails")
    func newSurvivorFails() {
        let result = gate.evaluate(
            summary(killed: 1, survived: ["a", "new"]),
            policy: GatePolicy(maxNewSurvivors: 0),
            baseline: makeBaseline(undetected: ["a"])
        )

        #expect(result.newUndetected.map(\.descriptor.fingerprint) == ["new"])
        #expect(result.checks == [.newUndetected(count: 1, maximum: 0)])
        #expect(!result.passed)
    }

    @Test("Given a new mutant without coverage, when evaluated, then it counts as a new undetected mutant")
    func newNoCoverageCounts() {
        let result = gate.evaluate(
            summary(killed: 1, noCoverage: ["uncovered"]),
            policy: GatePolicy(maxNewSurvivors: 0),
            baseline: makeBaseline()
        )

        #expect(result.newUndetected.map(\.descriptor.fingerprint) == ["uncovered"])
        #expect(!result.passed)
    }

    @Test("Given new survivors within the maximum, when evaluated, then the gate passes")
    func newSurvivorsWithinTheMaximumPass() {
        let result = gate.evaluate(
            summary(killed: 1, survived: ["x", "y"]),
            policy: GatePolicy(maxNewSurvivors: 2),
            baseline: makeBaseline()
        )

        #expect(result.passed)
    }

    @Test("Given baseline mutants that are detected now, when evaluated, then they are counted as fixed")
    func countsMutantsFixedSinceTheBaseline() {
        let result = gate.evaluate(
            summary(killed: 3, survived: ["a"]),
            policy: GatePolicy(maxNewSurvivors: 0),
            baseline: makeBaseline(undetected: ["a", "b", "c"])
        )

        #expect(result.fixedCount == 2)
    }

    @Test("Given every policy and one failing, when evaluated, then all are checked and the gate fails")
    func combinedPoliciesFailWhenOneFails() {
        let result = gate.evaluate(
            summary(killed: 9, survived: ["a"]),
            policy: GatePolicy(minScore: 80, maxScoreDrop: 2, maxNewSurvivors: 0),
            baseline: makeBaseline(score: 90, undetected: [])
        )

        #expect(result.checks.count == 3)
        #expect(result.checks.filter(\.passed).count == 2)
        #expect(!result.passed)
    }

    @Test("Given no baseline, when evaluated with baseline policies, then only the minimum score is checked")
    func baselinePoliciesNeedABaseline() {
        let result = gate.evaluate(
            summary(killed: 1),
            policy: GatePolicy(minScore: 50, maxScoreDrop: 0, maxNewSurvivors: 0),
            baseline: nil
        )

        #expect(result.checks == [.minScore(score: 100, minimum: 50)])
        #expect(result.fixedCount == nil)
    }

    @Test("Given integrity warnings within the maximum and no baseline, when evaluated, then the gate passes")
    func integrityWarningsWithinTheMaximumPass() {
        let result = gate.evaluate(
            withIntegrityWarnings(2), policy: GatePolicy(maxIntegrityWarnings: 2), baseline: nil
        )

        #expect(result.checks == [.integrityWarnings(count: 2, maximum: 2)])
        #expect(result.passed)
    }

    @Test("Given an integrity warning and a maximum of zero, when evaluated, then the gate fails")
    func anIntegrityWarningAboveTheMaximumFails() {
        let result = gate.evaluate(
            withIntegrityWarnings(1), policy: GatePolicy(maxIntegrityWarnings: 0), baseline: nil
        )

        #expect(result.checks == [.integrityWarnings(count: 1, maximum: 0)])
        #expect(!result.passed)
    }

    @Test("Given integrity warnings and no maximum, when evaluated, then they are not checked")
    func integrityWarningsWithoutAMaximumAreNotChecked() {
        let result = gate.evaluate(withIntegrityWarnings(3), policy: GatePolicy(minScore: 0), baseline: nil)

        #expect(result.checks == [.minScore(score: 100, minimum: 0)])
    }

    @Test("Given new undetected mutants in several files, when evaluated, then they are listed by file and line")
    func newUndetectedAreSortedByLocation() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(filePath: "/p/B.swift", line: 1, status: .survived, fingerprint: "b1"),
                makeExecutionResult(filePath: "/p/A.swift", line: 9, status: .survived, fingerprint: "a9"),
                makeExecutionResult(filePath: "/p/A.swift", line: 2, status: .survived, fingerprint: "a2"),
            ],
            totalDuration: 0
        )

        let result = gate.evaluate(summary, policy: GatePolicy(maxNewSurvivors: 0), baseline: makeBaseline())

        #expect(result.newUndetected.map(\.descriptor.fingerprint) == ["a2", "a9", "b1"])
    }

    @Test(
        "Given a check, when asked whether it passed, then it compares against its bound",
        arguments: [
            (GateResult.Check.minScore(score: 79.9, minimum: 80), false),
            (.minScore(score: 80, minimum: 80), true),
            (.minScore(score: nil, minimum: 0), false),
            (.scoreDrop(drop: 2.1, maximum: 2), false),
            (.scoreDrop(drop: -3, maximum: 0), true),
            (.scoreDrop(drop: nil, maximum: 100), false),
            (.newUndetected(count: 1, maximum: 0), false),
            (.newUndetected(count: 0, maximum: 0), true),
            (.integrityWarnings(count: 1, maximum: 0), false),
            (.integrityWarnings(count: 0, maximum: 0), true),
        ]
    )
    func checkPassesWithinItsBound(check: GateResult.Check, passed: Bool) {
        #expect(check.passed == passed)
    }

    private func summary(killed: Int, survived: [String] = [], noCoverage: [String] = []) -> RunnerSummary {
        RunnerSummary(
            results: (0 ..< killed).map { makeExecutionResult(status: .killed(by: "t"), fingerprint: "killed-\($0)") }
                + survived.map { makeExecutionResult(status: .survived, fingerprint: $0) }
                + noCoverage.map { makeExecutionResult(status: .noCoverage, fingerprint: $0) },
            totalDuration: 0
        )
    }

    private func withIntegrityWarnings(_ count: Int) -> RunnerSummary {
        RunnerSummary(
            results: (0 ..< count).map {
                makeExecutionResult(status: .killed(by: "flaky"), fingerprint: "unactivated-\($0)", activated: false)
            } + [makeExecutionResult(status: .killed(by: "t"), fingerprint: "activated", activated: true)],
            totalDuration: 0
        )
    }
}
