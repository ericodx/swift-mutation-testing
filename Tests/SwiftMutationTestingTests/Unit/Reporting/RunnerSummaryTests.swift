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

    @Test("Given results with all statuses, when partitioned, then timeouts are detected and unviable is neither")
    func detectedAndUndetectedPartition() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(status: .killed(by: "Suite.test")),
                makeExecutionResult(status: .killedByCrash),
                makeExecutionResult(status: .timeout),
                makeExecutionResult(status: .survived),
                makeExecutionResult(status: .noCoverage),
                makeExecutionResult(status: .unviable),
            ],
            totalDuration: 0
        )

        #expect(summary.detected.map(\.status) == [.killed(by: "Suite.test"), .killedByCrash, .timeout])
        #expect(summary.undetected.map(\.status) == [.survived, .noCoverage])
    }

    @Test(
        "Given a single mutant of each status, when score computed, then detection scores 100 and the rest 0",
        arguments: [
            (ExecutionStatus.killed(by: "t"), 100.0),
            (.killedByCrash, 100.0),
            (.timeout, 100.0),
            (.survived, 0.0),
            (.noCoverage, 0.0),
            (.unviable, 100.0),
        ]
    )
    func scoreOfEachStatusAlone(status: ExecutionStatus, expected: Double) {
        let summary = RunnerSummary(results: [makeExecutionResult(status: status)], totalDuration: 0)

        #expect(summary.score == expected)
    }

    @Test("Given timeouts and no survivors, when score computed, then score is 100")
    func timeoutsWithoutSurvivorsScoreHundred() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(status: .killed(by: "t")),
                makeExecutionResult(status: .timeout),
                makeExecutionResult(status: .timeout),
            ],
            totalDuration: 0
        )

        #expect(summary.score == 100.0)
    }

    @Test("Given every status mixed, when score computed, then timeouts count as detected")
    func scoreCountsTimeoutsAsDetected() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(status: .killed(by: "t")),
                makeExecutionResult(status: .killedByCrash),
                makeExecutionResult(status: .timeout),
                makeExecutionResult(status: .survived),
                makeExecutionResult(status: .survived),
                makeExecutionResult(status: .noCoverage),
                makeExecutionResult(status: .unviable),
            ],
            totalDuration: 0
        )

        #expect(summary.score == 50.0)
    }

    @Test("Given a mixed summary, when the detection line is built, then it breaks both sides down")
    func detectionLineBreaksDownBothSides() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(status: .killed(by: "t")),
                makeExecutionResult(status: .killedByCrash),
                makeExecutionResult(status: .timeout),
                makeExecutionResult(status: .survived),
                makeExecutionResult(status: .noCoverage),
                makeExecutionResult(status: .unviable),
            ],
            totalDuration: 0
        )

        #expect(
            summary.detectionLine
                == "Detected: 3 (killed 2, timeout 1) / Undetected: 2 (survived 1, no coverage 1)"
        )
    }

    @Test("Given results in several files, when summarised per file, then they come in path order with own counts")
    func filesComeInPathOrderWithTheirOwnCounts() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "b0", filePath: "/p/B.swift", status: .survived),
                makeExecutionResult(id: "a0", filePath: "/p/A.swift", status: .killed(by: "t")),
                makeExecutionResult(id: "a1", filePath: "/p/A.swift", status: .noCoverage),
            ],
            totalDuration: 3
        )

        #expect(summary.files.map(\.path) == ["/p/A.swift", "/p/B.swift"])
        #expect(summary.files.map(\.summary.killed.count) == [1, 0])
        #expect(summary.files.map(\.summary.undetected.count) == [1, 1])
        #expect(summary.files.allSatisfy { $0.summary.totalDuration == 0 })
    }

    @Test("Given results out of order, when put in source order, then they follow file, line and column")
    func byLocationFollowsFileLineAndColumn() {
        let results = [
            makeExecutionResult(id: "3", filePath: "/p/B.swift", line: 1, column: 1, status: .survived),
            makeExecutionResult(id: "2", filePath: "/p/A.swift", line: 2, column: 9, status: .survived),
            makeExecutionResult(id: "1", filePath: "/p/A.swift", line: 2, column: 3, status: .survived),
            makeExecutionResult(id: "0", filePath: "/p/A.swift", line: 1, column: 5, status: .survived),
        ]

        #expect(RunnerSummary.byLocation(results).map(\.descriptor.id) == ["0", "1", "2", "3"])
    }

    @Test("Given cached, unactivated and unmeasured results, when summarised, then each list holds the right ones")
    func theActivationAndCacheListsAreBuiltWithTheSummary() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "a", status: .killed(by: "t"), activated: false),
                makeExecutionResult(id: "b", status: .timeout, activated: false),
                makeExecutionResult(id: "c", status: .survived, activated: false),
                makeExecutionResult(id: "d", status: .survived, activated: nil, fromCache: true),
                makeExecutionResult(id: "e", status: .unviable, activated: nil),
            ],
            totalDuration: 0
        )

        #expect(summary.integrityWarnings.map(\.descriptor.id) == ["a", "b"])
        #expect(summary.activationNotMeasured.map(\.descriptor.id) == ["d"])
        #expect(summary.fromCache.map(\.descriptor.id) == ["d"])
        #expect(summary.resultsByFile.values.flatMap { $0 }.count == 5)
    }
}
