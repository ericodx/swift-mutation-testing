import Testing

@testable import SwiftMutationTesting

@Suite("TextReporter")
struct TextReporterTests {
    @Test("Given a known summary, when format called, then output contains score and counts")
    func formatContainsScoreAndCounts() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(line: 3, column: 5, status: .killed(by: "Suite.test")),
                makeExecutionResult(line: 3, column: 5, status: .killed(by: "Suite.test")),
                makeExecutionResult(line: 3, column: 5, status: .survived),
                makeExecutionResult(line: 3, column: 5, status: .unviable),
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

    @Test("Given survived mutants, when format called, then the undetected section lists file, operator and status")
    func formatListsSurvivedMutants() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(filePath: "/abs/Sources/Foo.swift", line: 3, column: 5, status: .survived)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Undetected mutants:"))
        #expect(output.contains("/abs/Sources/Foo.swift:3:5   ArithmeticOperatorReplacement   survived"))
    }

    @Test("Given only unviable mutants, when format called, then the undetected section is absent")
    func formatOmitsSurvivedSectionWhenNone() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(line: 3, column: 5, status: .unviable)], totalDuration: 0)

        let output = TextReporter().format(summary)

        #expect(!output.contains("Undetected mutants:"))
    }

    @Test("Given results by file, when format called, then results by file section is present")
    func formatContainsResultsByFile() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(filePath: "/abs/Sources/Calc.swift", line: 3, column: 5, status: .killed(by: "t"))
            ],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Results by file:"))
        #expect(output.contains("/abs/Sources/Calc.swift"))
    }

    @Test("Given projectRoot set, when format called, then file paths are shown relative to root")
    func formatShowsRelativePaths() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(filePath: "/proj/Sources/Calc.swift", line: 3, column: 5, status: .survived)],
            totalDuration: 0
        )

        let output = TextReporter(projectRoot: "/proj").format(summary)

        #expect(output.contains("Sources/Calc.swift"))
        #expect(!output.contains("/proj/Sources/Calc.swift"))
    }

    @Test("Given path outside project root, when format called, then full path is shown unchanged")
    func formatShowsFullPathWhenOutsideRoot() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(filePath: "/other/Sources/Calc.swift", line: 3, column: 5, status: .survived)
            ],
            totalDuration: 0
        )

        let output = TextReporter(projectRoot: "/proj").format(summary)

        #expect(output.contains("/other/Sources/Calc.swift"))
    }

    @Test("Given a summary, when report called, then output is printed to stdout")
    func reportPrintsToStdout() async {
        let summary = RunnerSummary(
            results: [makeExecutionResult(filePath: "/tmp/Foo.swift", line: 3, column: 5, status: .killed(by: "t"))],
            totalDuration: 1.0
        )

        let output = await captureOutput {
            TextReporter().report(summary)
        }

        #expect(output.contains("Overall mutation score:"))
    }

    @Test("Given only unviable mutants, when format called, then the overall and file scores are n/a")
    func formatShowsNoScoreWithoutTestedMutants() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(filePath: "/tmp/Foo.swift", status: .unviable)],
            totalDuration: 1.0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Overall mutation score: n/a"))
        #expect(output.contains("score: n/a"))
    }

    @Test("Given timeout mutant, when format called, then timeout count appears in results by file")
    func formatShowsTimeoutInResultsByFile() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(filePath: "/abs/Sources/Foo.swift", line: 3, column: 5, status: .timeout)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("timeout: 1"))
        #expect(output.contains("Timeouts: 1"))
    }

    @Test("Given killed, timed-out and survived mutants, when format called, then the detection line follows the score")
    func formatShowsDetectionLineAfterScore() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(line: 3, column: 5, status: .killed(by: "Suite.test")),
                makeExecutionResult(line: 3, column: 5, status: .timeout),
                makeExecutionResult(line: 3, column: 5, status: .survived),
            ],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(
            output.contains(
                "Overall mutation score: 66.7%\n"
                    + "Detected: 2 (killed 1, timeout 1) / Undetected: 1 (survived 1, no coverage 0)\n"
                    + "Killed: 1 / Survived: 1 / Timeouts: 1 / Unviable: 0 / NoCoverage: 0"
            ))
    }

    @Test("Given killedByCrash mutant, when format called, then killed count includes crash")
    func formatCountsKilledByCrashAsKilled() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(line: 3, column: 5, status: .killedByCrash)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("killed: 1"))
    }

    @Test("Given two survived mutants in different files, when format called, then both sorted in survived section")
    func twoSurvivedMutantsAreSortedInOutput() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(filePath: "/abs/Sources/Z.swift", line: 3, column: 5, status: .survived),
                makeExecutionResult(filePath: "/abs/Sources/A.swift", line: 3, column: 5, status: .survived),
            ],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Undetected mutants:"))
        let aIndex = output.range(of: "/abs/Sources/A.swift")?.lowerBound
        let zIndex = output.range(of: "/abs/Sources/Z.swift")?.lowerBound
        #expect(aIndex != nil && zIndex != nil)
        #expect(aIndex! < zIndex!)
    }

    @Test("Given duration over 60 seconds, when format called, then duration is shown in minutes and seconds")
    func formatShowsDurationInMinutes() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(line: 3, column: 5, status: .killed(by: "t"))],
            totalDuration: 1825.4
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("30m 25s"))
    }

    @Test("Given a no-coverage mutant, when format called, then it is listed as undetected with no coverage")
    func noCoverageIsListedAsUndetected() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(filePath: "/abs/Foo.swift", line: 3, column: 5, status: .noCoverage)],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("Undetected mutants:"))
        #expect(output.contains("/abs/Foo.swift:3:5   ArithmeticOperatorReplacement   no coverage"))
        #expect(!output.contains("Survived mutants:"))
    }

    @Test("Given mutants of every status in a file, when format called, then its line counts no coverage too")
    func perFileStatsCountNoCoverage() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "0", filePath: "/abs/Foo.swift", status: .killed(by: "t")),
                makeExecutionResult(id: "1", filePath: "/abs/Foo.swift", status: .noCoverage),
                makeExecutionResult(id: "2", filePath: "/abs/Foo.swift", status: .noCoverage),
            ],
            totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(output.contains("killed: 1   survived: 0   timeout: 0   unviable: 0   no coverage: 2"))
    }
}
