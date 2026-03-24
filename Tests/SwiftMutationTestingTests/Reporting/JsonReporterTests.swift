import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("JsonReporter")
struct JsonReporterTests {
    @Test("Given a summary, when report called, then output is parseable JSON with mutation report schema")
    func reportProducesParseableMutationJson() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let projectRoot = "/abs/MyApp"
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: projectRoot)

        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "Suite.test"))],
            totalDuration: 5
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["schemaVersion"] as? String == "1")
        #expect(json?["projectRoot"] as? String == projectRoot)
        let files = json?["files"] as? [String: Any]
        #expect(files?["/Sources/Calc.swift"] != nil)
    }

    @Test("Given a killed mutant, when report called, then status string is Killed")
    func killedMutantProducesKilledStatus() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "t"))],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]

        #expect(mutants?.first?["status"] as? String == "Killed")
    }

    @Test("Given a mutant, when report called, then file key includes leading slash relative to project root")
    func fileKeyIncludesLeadingSlashRelativeToProjectRoot() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]

        #expect(files?["/Sources/Calc.swift"] != nil)
        #expect(files?["Sources/Calc.swift"] == nil)
    }

    @Test("Given a killed mutant, when report called, then killedBy contains the test name")
    func killedMutantPopulatesKilledBy() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .killed(by: "MySuite.myTest"))],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]

        #expect(mutants?.first?["killedBy"] as? String == "MySuite.myTest")
    }

    @Test("Given a survived mutant, when report called, then killedBy is nil")
    func survivedMutantHasNilKilledBy() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]
        let killedBy = mutants?.first?["killedBy"]

        #expect(killedBy == nil || killedBy is NSNull)
    }

    @Test("Given a mutant, when report called, then originalText is present in the mutant entry")
    func mutantEntryContainsOriginalText() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]

        #expect(mutants?.first?["originalText"] as? String == "+")
    }

    @Test("Given a mutant, when report called, then end column equals start column plus original text length")
    func endColumnEqualsStartColumnPlusOriginalTextLength() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [makeResult(filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived)],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]
        let location = mutants?.first?["location"] as? [String: Any]
        let start = location?["start"] as? [String: Any]
        let end = location?["end"] as? [String: Any]

        let startColumn = start?["column"] as? Int ?? 0
        let endColumn = end?["column"] as? Int ?? 0

        #expect(endColumn == startColumn + "+".count)
    }

    private func makeResult(filePath: String, status: ExecutionStatus) -> ExecutionResult {
        ExecutionResult(
            descriptor: MutantDescriptor(
                id: "1",
                filePath: filePath,
                line: 3,
                column: 24,
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
