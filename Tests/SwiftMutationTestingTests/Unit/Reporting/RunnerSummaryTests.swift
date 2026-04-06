import Testing

@testable import SwiftMutationTesting

@Suite("RunnerSummary")
struct RunnerSummaryTests {
    @Test("Given results with all statuses, when properties accessed, then killed includes crashes")
    func groupsPartitionResultsByStatus() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(status: .killed(by: "Suite.test")),
                makeExecutionResult(status: .killedByCrash),
                makeExecutionResult(status: .survived),
                makeExecutionResult(status: .unviable),
                makeExecutionResult(status: .timeout),
                makeExecutionResult(status: .noCoverage),
            ],
            totalDuration: 10
        )

        #expect(summary.killed.count == 2)
        #expect(summary.survived.count == 1)
        #expect(summary.unviable.count == 1)
        #expect(summary.timeouts.count == 1)
        #expect(summary.noCoverage.count == 1)
    }

    @Test("Given killed and survived mutants, when score computed, then unviable is excluded from denominator")
    func scoreExcludesUnviableFromDenominator() {
        let results = [
            makeExecutionResult(status: .killed(by: "Suite.test")),
            makeExecutionResult(status: .killed(by: "Suite.test")),
            makeExecutionResult(status: .killed(by: "Suite.test")),
            makeExecutionResult(status: .survived),
            makeExecutionResult(status: .unviable),
        ]
        let summary = RunnerSummary(results: results, totalDuration: 0)

        #expect(summary.score == 75.0)
    }

    @Test("Given no scoreable mutants, when score computed, then score is 100")
    func scoreIsHundredWhenDenominatorIsZero() {
        let summary = RunnerSummary(results: [makeExecutionResult(status: .unviable)], totalDuration: 0)

        #expect(summary.score == 100.0)
    }

    @Test("Given results from two files, when resultsByFile accessed, then results are grouped by file path")
    func resultsByFileGroupsByFilePath() {
        let results = [
            makeExecutionResult(filePath: "/a/Foo.swift", status: .survived),
            makeExecutionResult(filePath: "/a/Foo.swift", status: .killed(by: "t")),
            makeExecutionResult(filePath: "/a/Bar.swift", status: .survived),
        ]
        let summary = RunnerSummary(results: results, totalDuration: 0)

        #expect(summary.resultsByFile["/a/Foo.swift"]?.count == 2)
        #expect(summary.resultsByFile["/a/Bar.swift"]?.count == 1)
    }

    @Test("Given mixed cached and fresh results, when score computed, then score reflects combined state")
    func scoreFromMixedCachedAndFreshResults() {
        let cachedKilled = makeExecutionResult(status: .killed(by: "T1"))
        let cachedSurvived = makeExecutionResult(status: .survived)
        let freshKilled = makeExecutionResult(status: .killed(by: "T2"))
        let freshSurvived = makeExecutionResult(status: .survived)

        let summary = RunnerSummary(
            results: [cachedKilled, cachedSurvived, freshKilled, freshSurvived],
            totalDuration: 5
        )

        #expect(summary.killed.count == 2)
        #expect(summary.survived.count == 2)
        #expect(summary.score == 50.0)
    }
}
