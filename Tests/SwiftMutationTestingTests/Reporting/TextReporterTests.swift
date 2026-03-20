import Testing

@testable import SwiftMutationTesting

@Suite("TextReporter")
struct TextReporterTests {
    @Test("Given a known summary, when format called, then output contains score and counts")
    func formatContainsScoreAndCounts() {
        let summary = RunnerSummary(
            results: [
                makeResult(status: .killed(by: "Suite.test")),
                makeResult(status: .killed(by: "Suite.test")),
                makeResult(status: .survived),
                makeResult(status: .unviable),
            ],
            totalDuration: 12.5
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("66.7%"))
        #expect(output.contains("Killed: 2"))
        #expect(output.contains("Survived: 1"))
        #expect(output.contains("Unviable: 1"))
        #expect(output.contains("12.5s"))
    }

    @Test("Given survived mutants, when format called, then survived section lists file and operator")
    func formatListsSurvivedMutants() {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/Sources/Foo.swift", status: .survived)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Survived mutants:"))
        #expect(output.contains("/abs/Sources/Foo.swift"))
        #expect(output.contains("ArithmeticOperatorReplacement"))
    }

    @Test("Given only unviable mutants, when format called, then survived section is absent")
    func formatOmitsSurvivedSectionWhenNone() {
        let summary = RunnerSummary(results: [makeResult(status: .unviable)], totalDuration: 0)

        let output = TextReporter().format(summary)

        #expect(!output.contains("Survived mutants:"))
    }

    @Test("Given results by file, when format called, then results by file section is present")
    func formatContainsResultsByFile() {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/Sources/Calc.swift", status: .killed(by: "t"))],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Results by file:"))
        #expect(output.contains("/abs/Sources/Calc.swift"))
    }

    @Test("Given projectRoot set, when format called, then file paths are shown relative to root")
    func formatShowsRelativePaths() {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/proj/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        let output = TextReporter(projectRoot: "/proj").format(summary)

        #expect(output.contains("Sources/Calc.swift"))
        #expect(!output.contains("/proj/Sources/Calc.swift"))
    }

    private func makeResult(
        filePath: String = "/tmp/Foo.swift",
        status: ExecutionStatus
    ) -> ExecutionResult {
        ExecutionResult(
            descriptor: MutantDescriptor(
                id: "m0",
                filePath: filePath,
                line: 3,
                column: 5,
                utf8Offset: 0,
                originalText: "+",
                mutatedText: "-",
                operatorIdentifier: "ArithmeticOperatorReplacement",
                replacementKind: .binaryOperator,
                description: "+ → -",
                isSchematizable: false,
                mutatedSourceContent: nil
            ),
            status: status,
            testDuration: 0
        )
    }
}
