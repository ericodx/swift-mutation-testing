import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SonarReporter")
struct SonarReporterTests {
    @Test("Given survived and noCoverage mutants, when report called, then both appear as issues")
    func reportEmitsSurvivedAndNoCoverageIssues() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("sonar.json").path
        let projectRoot = "/abs/MyApp"
        let reporter = SonarReporter(outputPath: outputPath, projectRoot: projectRoot)

        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .survived),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .noCoverage),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .killed(by: "t")),
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .unviable),
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let issues = json?["issues"] as? [[String: Any]]

        #expect(issues?.count == 2)
    }

    @Test("Given survived mutant, when report called, then severity is MAJOR")
    func survivedMutantHasMajorSeverity() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("sonar.json").path
        let reporter = SonarReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .survived)
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let issues = json?["issues"] as? [[String: Any]]

        #expect(issues?.first?["severity"] as? String == "MAJOR")
    }

    @Test("Given noCoverage mutant, when report called, then severity is MINOR")
    func noCoverageMutantHasMinorSeverity() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("sonar.json").path
        let reporter = SonarReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .noCoverage)
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let issues = json?["issues"] as? [[String: Any]]

        #expect(issues?.first?["severity"] as? String == "MINOR")
    }

    @Test("Given survived mutant, when report called, then filePath in issue is relative to project root")
    func filePathIsRelativeToProjectRoot() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("sonar.json").path
        let projectRoot = "/abs/MyApp"
        let reporter = SonarReporter(outputPath: outputPath, projectRoot: projectRoot)
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .survived)
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let issues = json?["issues"] as? [[String: Any]]
        let location = issues?.first?["primaryLocation"] as? [String: Any]

        #expect(location?["filePath"] as? String == "/Sources/Calc.swift")
    }
}
