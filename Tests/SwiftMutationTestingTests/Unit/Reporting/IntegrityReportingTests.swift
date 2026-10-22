import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Integrity reporting")
struct IntegrityReportingTests {

    @Test("Given results of every kind, when the summary is asked, then only unactivated kills and timeouts warn")
    func integrityWarningsAreUnactivatedKillsAndTimeouts() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "1", status: .killed(by: "t"), activated: false),
                makeExecutionResult(id: "2", status: .killedByCrash, activated: false),
                makeExecutionResult(id: "3", status: .timeout, activated: false),
                makeExecutionResult(id: "4", status: .killed(by: "t"), activated: true),
                makeExecutionResult(id: "5", status: .noCoverage, activated: false),
                makeExecutionResult(id: "6", status: .survived, activated: true),
                makeExecutionResult(id: "7", status: .killed(by: "t")),
                makeExecutionResult(id: "8", status: .unviable),
            ],
            totalDuration: 0
        )

        #expect(summary.integrityWarnings.map(\.descriptor.id) == ["1", "2", "3"])
        #expect(summary.activationNotMeasured.map(\.descriptor.id) == ["7"])
    }

    @Test(
        "Given a result, when its report reason is asked, then it names the crash and a missing activation",
        arguments: [
            (ExecutionStatus.killedByCrash, true, "crash"),
            (.killedByCrash, false, "crash without activation"),
            (.killedByCrash, nil, "crash"),
            (.killed(by: "t"), false, "killed without activation"),
            (.killed(by: "t"), true, nil),
            (.timeout, false, "timed out without activation"),
            (.timeout, true, nil),
            (.noCoverage, false, nil),
            (.survived, true, nil),
        ] as [(ExecutionStatus, Bool?, String?)]
    )
    func reportStatusReason(status: ExecutionStatus, activated: Bool?, reason: String?) {
        #expect(makeExecutionResult(status: status, activated: activated).reportStatusReason == reason)
    }

    @Test(
        "Given a parallel kill not repeated alone, when its reason is asked, then it names the test only if undetected",
        arguments: [
            (ExecutionStatus.survived, "shares() failed only while other workers ran"),
            (.noCoverage, "shares() failed only while other workers ran"),
            (.killed(by: "other()"), nil),
        ] as [(ExecutionStatus, String?)]
    )
    func unconfirmedKillReason(status: ExecutionStatus, reason: String?) {
        let result = makeExecutionResult(status: status, activated: true, unconfirmedKiller: "shares()")

        #expect(result.reportStatusReason == reason)
    }

    @Test("Given parallel kills not repeated alone, when the text summary is formatted, then they are listed")
    func textSummaryListsUnconfirmedKills() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    filePath: "/p/Sources/B.swift", line: 9, column: 3, status: .survived, activated: true,
                    unconfirmedKiller: "MyTests.FixtureTests.testRoundTrip"
                ),
                makeExecutionResult(
                    filePath: "/p/Sources/A.swift", line: 4, column: 7, status: .noCoverage, activated: false,
                    unconfirmedKiller: "shares()"
                ),
                makeExecutionResult(filePath: "/p/Sources/A.swift", line: 1, status: .survived, activated: true),
            ],
            totalDuration: 0
        )

        let output = TextReporter(projectRoot: "/p").format(summary)

        #expect(summary.unconfirmedKills.count == 2)
        #expect(
            output.contains(
                """

                Kills not repeated alone (2): a test failed only while other workers ran
                  Sources/A.swift:4:7   ArithmeticOperatorReplacement   shares()
                  Sources/B.swift:9:3   ArithmeticOperatorReplacement   MyTests.FixtureTests.testRoundTrip

                Overall mutation score:
                """
            )
        )
    }

    @Test("Given parallel kills not repeated alone, when the Markdown is formatted, then they are counted")
    func markdownCountsUnconfirmedKills() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(status: .survived, activated: true, unconfirmedKiller: "shares()")],
            totalDuration: 0
        )

        let markdown = MarkdownReporter(outputPath: "/unused", projectRoot: "/p").format(summary)

        #expect(markdown.contains("Kills not repeated alone: 1 mutant killed only while other workers ran"))
    }

    @Test("Given unactivated kills, when the text summary is formatted, then they are listed with their reason")
    func textSummaryListsIntegrityWarnings() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    filePath: "/p/Sources/B.swift", line: 9, column: 3, status: .timeout, activated: false
                ),
                makeExecutionResult(
                    filePath: "/p/Sources/A.swift", line: 4, column: 7, status: .killed(by: "t"), activated: false
                ),
                makeExecutionResult(filePath: "/p/Sources/A.swift", line: 1, status: .survived, activated: true),
                makeExecutionResult(filePath: "/p/Sources/C.swift", line: 2, status: .survived),
            ],
            totalDuration: 0
        )

        let output = TextReporter(projectRoot: "/p").format(summary)

        #expect(
            output.contains(
                """

                Integrity warnings (2): killed or timed out without the mutated code running
                  Sources/A.swift:4:7   ArithmeticOperatorReplacement   killed without activation
                  Sources/B.swift:9:3   ArithmeticOperatorReplacement   timed out without activation

                Overall mutation score:
                """
            )
        )
        #expect(output.contains("Activation not measured: 1 mutant\nTotal duration:"))
    }

    @Test("Given more warnings than are listed, when the text summary is formatted, then the rest are counted")
    func textSummaryTruncatesIntegrityWarnings() {
        let results = (1 ... TextReporter.integrityWarningsListed + 2).map {
            makeExecutionResult(id: "\($0)", line: $0, status: .killed(by: "t"), activated: false)
        }

        let output = TextReporter().format(RunnerSummary(results: results, totalDuration: 0))
        let lines = output.components(separatedBy: "\n")

        let listed = lines.filter { $0.hasSuffix("killed without activation") }.count
        #expect(listed == TextReporter.integrityWarningsListed)
        #expect(lines.contains("  and 2 more — see the JSON report"))
    }

    @Test("Given no warnings and everything measured, when the text summary is formatted, then nothing is added")
    func textSummaryStaysQuietWithoutWarnings() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(status: .killed(by: "t"), activated: true)], totalDuration: 0
        )

        let output = TextReporter().format(summary)

        #expect(!output.contains("Integrity warnings"))
        #expect(!output.contains("Activation not measured"))
    }

    @Test("Given a killed mutant whose code never ran, when the JSON is written, then the reason says so")
    func jsonCarriesTheActivationReason() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("mutation.json").path
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t"), activated: false)
            ],
            totalDuration: 0
        )

        try JsonReporter(outputPath: path, projectRoot: "/abs/MyApp").report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let mutants = (files?["/Sources/Calc.swift"] as? [String: Any])?["mutants"] as? [[String: Any]]

        #expect(mutants?.first?["status"] as? String == "Killed")
        #expect(mutants?.first?["statusReason"] as? String == "killed without activation")
    }

    @Test("Given warnings and unmeasured mutants, when the Markdown is formatted, then both are counted")
    func markdownCountsWarningsAndUnmeasured() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "1", status: .killed(by: "t"), activated: false),
                makeExecutionResult(id: "2", status: .survived),
                makeExecutionResult(id: "3", status: .survived),
            ],
            totalDuration: 0
        )

        let output = MarkdownReporter(outputPath: "/unused", projectRoot: "/p").format(summary)

        let warning = "⚠️ Integrity warnings: 1 mutant killed or timed out without the mutated code running"
        #expect(output.contains(warning + "\n"))
        #expect(output.contains("Activation not measured: 2 mutants"))
    }

    @Test("Given verdicts from the cache, when the summaries are formatted, then they say how many")
    func summariesCountCachedVerdicts() {
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "1", status: .killed(by: "t"), activated: true, fromCache: true),
                makeExecutionResult(id: "2", status: .killed(by: "t"), activated: true),
            ],
            totalDuration: 0
        )

        let text = TextReporter().format(summary)
        let markdown = MarkdownReporter(outputPath: "/unused", projectRoot: "/p").format(summary)

        #expect(text.contains("Verdicts from cache: 1 of 2\nTotal duration:"))
        #expect(markdown.contains("Verdicts from cache: 1 of 2"))
    }

    @Test("Given no verdict from the cache, when the text summary is formatted, then no cache line is added")
    func noCacheLineWithoutCachedVerdicts() {
        let summary = RunnerSummary(
            results: [makeExecutionResult(status: .killed(by: "t"), activated: true)], totalDuration: 0
        )

        #expect(!TextReporter().format(summary).contains("from cache"))
    }
}
