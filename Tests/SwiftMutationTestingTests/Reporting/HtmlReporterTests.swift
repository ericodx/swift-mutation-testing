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
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t"))],
            totalDuration: 1
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("Mutation Testing Report"))
    }

    @Test("Given a mutant, when report called, then file path uses leading slash relative to project root")
    func filePathIncludesLeadingSlashRelativeToProjectRoot() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")

        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("/Sources/Calc.swift"))
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
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t")),
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("Score:"))
        #expect(html.contains("50.0%"))
    }

    @Test("Given score of 100, when report called, then green class is applied to file row score cell")
    func scoreOf100AppliesGreenClassToTableRow() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let reporter = HtmlReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t"))],
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
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t")),
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived),
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
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived),
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived),
                makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t")),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(html.contains("class=\"score-red\""))
    }

    private func makeResult(filePath: String, status: ExecutionStatus) -> ExecutionResult {
        ExecutionResult(
            descriptor: MutantDescriptor(
                id: "1",
                filePath: filePath,
                line: 3,
                column: 10,
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
