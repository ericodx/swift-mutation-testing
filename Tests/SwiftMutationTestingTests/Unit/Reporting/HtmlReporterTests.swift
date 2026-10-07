import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("HtmlReporter")
struct HtmlReporterTests {
    @Test("Given a summary, when report called, then output is valid HTML")
    func reportProducesHtmlFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .killed(by: "t"))
            ],
            totalDuration: 1
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("Mutation Testing Report"))
    }

    @Test("Given a mutant, when report called, then file path is relative to project root")
    func filePathIsRelativeToProjectRoot() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .survived)
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("<td>Sources/Calc.swift<details>"))
        #expect(!html.contains("/abs/MyApp/Sources/Calc.swift"))
    }

    @Test("Given a summary, when report called, then score appears in output")
    func scorePresentInOutput() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .killed(by: "t")),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .survived),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("Score:"))
        #expect(html.contains("50.0%"))
    }

    @Test("Given a timed-out mutant, when report called, then the detection line counts it as detected")
    func detectionLinePresentInOutput() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .timeout),
                makeExecutionResult(
                    id: "2", filePath: "/abs/MyApp/Sources/Calc.swift", line: 4, column: 10, status: .survived),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("<p>Detected: 1 (killed 0, timeout 1) / Undetected: 1 (survived 1, no coverage 0)</p>"))
        #expect(html.contains("50.0%"))
    }

    @Test("Given score of 100, when report called, then green class is applied to file row score cell")
    func scoreOf100AppliesGreenClassToTableRow() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .killed(by: "t"))
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("class=\"score-green\""))
        #expect(!html.contains("class=\"score score-green\""))
    }

    @Test("Given score between 50 and 99, when report called, then yellow class is applied to file row score cell")
    func scoreBetween50And99AppliesYellowClassToTableRow() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .killed(by: "t")),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .survived),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("class=\"score-yellow\""))
    }

    @Test("Given score below 50, when report called, then red class is applied to file row score cell")
    func scoreBelow50AppliesRedClassToTableRow() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .survived),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .survived),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 10, status: .killed(by: "t")),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("class=\"score-red\""))
    }

    @Test("Given two survived mutants at different lines in same file, when report called, then sorted by line")
    func survivedMutantsSortedByLineInDetails() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 20, column: 10, status: .survived),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 5, column: 10, status: .survived),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("Survived mutants (2)"))
        let line5Index = html.range(of: "<td>5</td>")?.lowerBound
        let line20Index = html.range(of: "<td>20</td>")?.lowerBound
        #expect(line5Index != nil && line20Index != nil)
        #expect(line5Index! < line20Index!)
    }

    @Test("Given results in several files, when report called, then the files are listed in path order")
    func filesAreListedInPathOrder() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "1", filePath: "/abs/MyApp/Sources/Zebra.swift", status: .survived),
                makeExecutionResult(id: "2", filePath: "/abs/MyApp/Sources/Alpha.swift", status: .killed(by: "t")),
            ],
            totalDuration: 1
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        let alpha = try #require(html.range(of: "Alpha.swift"))
        let zebra = try #require(html.range(of: "Zebra.swift"))

        #expect(alpha.lowerBound < zebra.lowerBound)
    }

    @Test("Given a run with no results at all, when report called, then the report is written with no rows")
    func aRunWithoutResultsStillProducesAReport() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        try reporter.report(RunnerSummary(results: [], totalDuration: 0))

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(!html.contains("<tr class="))
    }

    @Test("Given a relational and a logical mutation, when report called, then their operators are escaped")
    func operatorTextIsEscaped() throws {
        let html = try reportedHtml(
            survived: [
                makeMutantDescriptor(id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", description: "< → <="),
                makeMutantDescriptor(id: "2", filePath: "/abs/MyApp/Sources/Calc.swift", description: "&& → ||"),
            ]
        )

        #expect(html.contains("<td>&lt; → &lt;=</td>"))
        #expect(html.contains("<td>&amp;&amp; → ||</td>"))
        #expect(!html.contains("<td>< → <=</td>"))
    }

    @Test("Given a string literal mutation with markup, when report called, then the markup is not injected")
    func literalMarkupIsNotInjected() throws {
        let html = try reportedHtml(
            survived: [
                makeMutantDescriptor(
                    filePath: "/abs/MyApp/Sources/Calc.swift",
                    description: "\"<script>alert('x')</script>\" → \"\""
                )
            ]
        )

        #expect(!html.contains("<script>"))
        #expect(html.contains("&quot;&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;&quot; → &quot;&quot;"))
    }

    @Test("Given a project root reached through a symlink, when report called, then the file path is relative")
    func aSymlinkedProjectRootStillGivesARelativePath() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let link = dir.appendingPathComponent("link")
        let real = dir.appendingPathComponent("real")
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let resolvedFile = real.resolvingSymlinksInPath().appendingPathComponent("Sources/Calc.swift").path
        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: link.path)

        try reporter.report(
            RunnerSummary(
                results: [makeExecutionResult(filePath: resolvedFile, status: .survived)],
                totalDuration: 0
            )
        )

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("<td>Sources/Calc.swift<details>"))
    }

    private func reportedHtml(survived descriptors: [MutantDescriptor]) throws -> String {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let results = descriptors.map {
            ExecutionResult(descriptor: $0, status: .survived, testDuration: 0)
        }

        try reporter.report(RunnerSummary(results: results, totalDuration: 0))

        return try String(contentsOfFile: outputPath, encoding: .utf8)
    }
}
