import Testing

@testable import SwiftMutationTesting

@Suite("RunnerSummary")
struct RunnerSummaryTests {
    @Test("Given results with all statuses, when properties accessed, then each group contains only matching results")
    func groupsPartitionResultsByStatus() {
        let summary = RunnerSummary(results: makeResults(), totalDuration: 10)

        #expect(summary.killed.count == 1)
        #expect(summary.crashes.count == 1)
        #expect(summary.survived.count == 1)
        #expect(summary.unviable.count == 1)
        #expect(summary.timeouts.count == 1)
        #expect(summary.noCoverage.count == 1)
    }

    @Test("Given killed and survived mutants, when score computed, then unviable is excluded from denominator")
    func scoreExcludesUnviableFromDenominator() {
        let results = [
            makeResult(status: .killed(by: "Suite.test")),
            makeResult(status: .killed(by: "Suite.test")),
            makeResult(status: .killed(by: "Suite.test")),
            makeResult(status: .survived),
            makeResult(status: .unviable),
        ]
        let summary = RunnerSummary(results: results, totalDuration: 0)

        #expect(summary.score == 75.0)
    }

    @Test("Given no scoreable mutants, when score computed, then score is 100")
    func scoreIsHundredWhenDenominatorIsZero() {
        let summary = RunnerSummary(results: [makeResult(status: .unviable)], totalDuration: 0)

        #expect(summary.score == 100.0)
    }

    @Test("Given results from two files, when resultsByFile accessed, then results are grouped by file path")
    func resultsByFileGroupsByFilePath() {
        let results = [
            makeResult(filePath: "/a/Foo.swift", status: .survived),
            makeResult(filePath: "/a/Foo.swift", status: .killed(by: "t")),
            makeResult(filePath: "/a/Bar.swift", status: .survived),
        ]
        let summary = RunnerSummary(results: results, totalDuration: 0)

        #expect(summary.resultsByFile["/a/Foo.swift"]?.count == 2)
        #expect(summary.resultsByFile["/a/Bar.swift"]?.count == 1)
    }

    private func makeResults() -> [ExecutionResult] {
        [
            makeResult(status: .killed(by: "Suite.test")),
            makeResult(status: .killedByCrash),
            makeResult(status: .survived),
            makeResult(status: .unviable),
            makeResult(status: .timeout),
            makeResult(status: .noCoverage),
        ]
    }

    private func makeResult(filePath: String = "/tmp/Foo.swift", status: ExecutionStatus) -> ExecutionResult {
        ExecutionResult(descriptor: makeDescriptor(filePath: filePath), status: status, testDuration: 0)
    }

    private func makeDescriptor(filePath: String = "/tmp/Foo.swift") -> MutantDescriptor {
        MutantDescriptor(
            id: "m0",
            filePath: filePath,
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "+",
            mutatedText: "-",
            operatorIdentifier: "ArithmeticOperatorReplacement",
            replacementKind: .binaryOperator,
            description: "+ → -",
            isSchematizable: false,
            mutatedSourceContent: nil
        )
    }
}
