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

    @Test("Given path outside project root, when format called, then full path is shown unchanged")
    func formatShowsFullPathWhenOutsideRoot() {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/other/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        let output = TextReporter(projectRoot: "/proj").format(summary)

        #expect(output.contains("/other/Sources/Calc.swift"))
    }

    @Test("Given a summary, when report called, then output is printed to stdout")
    func reportPrintsToStdout() async {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/tmp/Foo.swift", status: .killed(by: "t"))],
            totalDuration: 1.0
        )

        let output = await captureOutput {
            TextReporter().report(summary)
        }

        #expect(output.contains("Overall mutation score:"))
    }

    @Test("Given timeout mutant, when format called, then timeout count appears in results by file")
    func formatShowsTimeoutInResultsByFile() {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/Sources/Foo.swift", status: .timeout)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("timeout: 1"))
        #expect(output.contains("Timeouts: 1"))
    }

    @Test("Given killedByCrash mutant, when format called, then killed count includes crash")
    func formatCountsKilledByCrashAsKilled() {
        let summary = RunnerSummary(
            results: [makeResult(status: .killedByCrash)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("killed: 1"))
    }

    @Test("Given two survived mutants in different files, when format called, then both sorted in survived section")
    func twoSurvivedMutantsAreSortedInOutput() {
        let summary = RunnerSummary(
            results: [
                makeResult(filePath: "/abs/Sources/Z.swift", status: .survived),
                makeResult(filePath: "/abs/Sources/A.swift", status: .survived),
            ],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Survived mutants:"))
        let aIndex = output.range(of: "/abs/Sources/A.swift")?.lowerBound
        let zIndex = output.range(of: "/abs/Sources/Z.swift")?.lowerBound
        #expect(aIndex != nil && zIndex != nil)
        #expect(aIndex! < zIndex!)
    }

    @Test("Given duration over 60 seconds, when format called, then duration is shown in minutes and seconds")
    func formatShowsDurationInMinutes() {
        let summary = RunnerSummary(
            results: [makeResult(status: .killed(by: "t"))],
            totalDuration: 1825.4
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("30m 25s"))
    }

    @Test("Given noCoverage mutant, when format called, then it appears in survived section")
    func noCoverageAppearsInSurvivedSection() {
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/Foo.swift", status: .noCoverage)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Survived mutants:"))
        #expect(output.contains("/abs/Foo.swift"))
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
