import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SarifReporter")
struct SarifReporterTests {
    @Test("Given every status, when reported, then only survived and no-coverage mutants become results")
    func reportsOnlyUndetectedMutants() throws {
        let log = try report([
            makeExecutionResult(id: "1", status: .killed(by: "t")),
            makeExecutionResult(id: "2", status: .killedByCrash),
            makeExecutionResult(id: "3", status: .timeout),
            makeExecutionResult(id: "4", status: .unviable),
            makeExecutionResult(id: "5", line: 2, status: .survived, fingerprint: "survived"),
            makeExecutionResult(id: "6", line: 1, status: .noCoverage, fingerprint: "uncovered"),
        ])

        let results = try results(of: log)
        let properties = results.compactMap { $0["properties"] as? [String: Any] }

        #expect(results.count == 2)
        #expect(properties.compactMap { $0["mutationStatus"] as? String } == ["noCoverage", "survived"])
        #expect(results.allSatisfy { $0["level"] as? String == "warning" })
    }

    @Test("Given a survivor and an uncovered mutant, when reported, then each message says what went unnoticed")
    func messagesDescribeTheMutation() throws {
        let results = try results(
            of: report([
                makeExecutionResult(line: 1, status: .survived),
                makeExecutionResult(line: 2, status: .noCoverage),
            ])
        )
        let messages = results.compactMap { ($0["message"] as? [String: Any])?["text"] as? String }

        #expect(
            messages == [
                "Mutant survived: + → -. No test failed when this code was changed.",
                "Mutant survived: + → -. No test executed this code.",
            ]
        )
    }

    @Test("Given mutants of two operators, when reported, then there is one rule per operator present")
    func rulesAreTheOperatorsPresent() throws {
        let log = try report([
            makeExecutionResult(id: "1", line: 1, status: .survived, operatorIdentifier: "SwapTernary"),
            makeExecutionResult(id: "2", line: 2, status: .survived, operatorIdentifier: "NegateConditional"),
            makeExecutionResult(id: "3", line: 3, status: .survived, operatorIdentifier: "SwapTernary"),
            makeExecutionResult(id: "4", line: 4, status: .killed(by: "t"), operatorIdentifier: "RemoveSideEffects"),
        ])

        let rules = try #require(driver(of: log)["rules"] as? [[String: Any]])
        let results = try results(of: log)

        #expect(rules.compactMap { $0["id"] as? String } == ["NegateConditional", "SwapTernary"])
        #expect(results.compactMap { $0["ruleIndex"] as? Int } == [1, 0, 1])
        #expect(rules.allSatisfy { ($0["helpUri"] as? String)?.hasSuffix("#operator-identifiers") == true })
        #expect(rules.allSatisfy { ($0["fullDescription"] as? [String: Any])?["text"] is String })
    }

    @Test("Given an operator the catalog does not know, when its rule is made, then it still has a description")
    func unknownOperatorGetsADefaultRule() {
        let rule = SarifRuleCatalog.rule(for: "FutureOperator")

        #expect(rule.shortDescription.text == "FutureOperator")
        #expect(rule.fullDescription.text == "Mutates the code.")
    }

    @Test("Given a mutant, when reported, then its location is relative to the project root base")
    func locationIsProjectRelative() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let log = try report(
            [makeExecutionResult(filePath: dir.appendingPathComponent("Sources/A.swift").path, status: .survived)],
            projectRoot: dir.path
        )

        let artifact = try #require(physicalLocation(of: log)["artifactLocation"] as? [String: Any])
        let base = try #require(run(of: log)["originalUriBaseIds"] as? [String: [String: String]])

        #expect(artifact["uri"] as? String == "Sources/A.swift")
        #expect(artifact["uriBaseId"] as? String == "%SRCROOT%")
        let root = URL(fileURLWithPath: CanonicalPath.make(for: dir.path) + "/").absoluteString
        #expect(base["%SRCROOT%"]?["uri"] == root)
    }

    @Test("Given a line with multibyte characters before the mutant, when reported, then columns are UTF-16 based")
    func columnsAreUTF16CodeUnits() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let file = dir.appendingPathComponent("Café.swift")
        try "let x = 1\nlet preço = \"ação\" == b\n".write(to: file, atomically: true, encoding: .utf8)
        let utf8Column = Array("let preço = \"ação\" ".utf8).count + 1

        let log = try report(
            [
                ExecutionResult(
                    descriptor: makeMutantDescriptor(
                        filePath: file.path, line: 2, column: utf8Column, originalText: "==", mutatedText: "!="
                    ),
                    status: .survived,
                    testDuration: 0
                )
            ],
            projectRoot: dir.path
        )

        let region = try #require(physicalLocation(of: log)["region"] as? [String: Int])

        #expect(region["startLine"] == 2)
        #expect(region["startColumn"] == "let preço = \"ação\" ".utf16.count + 1)
        #expect(region["endColumn"] == "let preço = \"ação\" ==".utf16.count + 1)
        #expect(try run(of: log)["columnKind"] as? String == "utf16CodeUnits")
    }

    @Test("Given a file that cannot be read, when reported, then the recorded column is kept")
    func unreadableFileKeepsTheColumn() throws {
        let log = try report([makeExecutionResult(filePath: "/nonexistent/A.swift", column: 7, status: .survived)])

        let region = try #require(physicalLocation(of: log)["region"] as? [String: Int])

        #expect(region["startColumn"] == 7)
        #expect(region["endColumn"] == 8)
    }

    @Test("Given a mutant, when reported, then its fingerprint is a partial fingerprint and its change a property")
    func carriesTheFingerprintAndReplacement() throws {
        let log = try report([makeExecutionResult(status: .survived, fingerprint: "abc")])
        let result = try #require(try results(of: log).first)

        #expect((result["partialFingerprints"] as? [String: String]) == ["swiftMutationTesting/v1": "abc"])
        #expect((result["properties"] as? [String: String])?["replacement"] == "-")
    }

    @Test("Given more undetected mutants than the limit, when reported, then the first ones by location are kept")
    func truncatesAtTheLimit() throws {
        let summary = RunnerSummary(
            results: (1 ... 5).reversed().map { makeExecutionResult(id: "\($0)", line: $0, status: .survived) },
            totalDuration: 0
        )

        var log: SarifLog?
        let warning = captureErrorsSync {
            log = SarifReporter(outputPath: "/unused", projectRoot: "/tmp", resultLimit: 3).buildLog(summary)
        }

        #expect(log?.runs[0].results.map { $0.locations[0].physicalLocation.region.startLine } == [1, 2, 3])
        #expect(warning.hasPrefix("Warning: the SARIF report lists the first 3 of 5 undetected mutants"))
    }

    @Test("Given a summary, when reported, then the log names the schema, the version and the tool")
    func describesTheLogAndTool() throws {
        let log = try report([makeExecutionResult(status: .survived)])
        let driver = try driver(of: log)

        #expect(log["$schema"] as? String == "https://json.schemastore.org/sarif-2.1.0.json")
        #expect(log["version"] as? String == "2.1.0")
        #expect(driver["name"] as? String == "swift-mutation-testing")
        #expect(driver["version"] as? String == Version.number)
    }

    // MARK: - Helpers

    @Test("Given the file system root as the project, when reported, then the base URI is the root once")
    func theRootAsTheProjectHasOneSlash() throws {
        let log = try report([makeExecutionResult(filePath: "/A.swift", status: .survived)], projectRoot: "/")

        let base = try #require(run(of: log)["originalUriBaseIds"] as? [String: [String: String]])
        #expect(base["%SRCROOT%"]?["uri"] == "file:///")
    }

    private func report(_ results: [ExecutionResult], projectRoot: String = "/tmp") throws -> [String: Any] {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("report.sarif").path

        try SarifReporter(outputPath: path, projectRoot: projectRoot)
            .report(RunnerSummary(results: results, totalDuration: 0))

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func run(of log: [String: Any]) throws -> [String: Any] {
        try #require((log["runs"] as? [[String: Any]])?.first)
    }

    private func driver(of log: [String: Any]) throws -> [String: Any] {
        try #require((try run(of: log)["tool"] as? [String: Any])?["driver"] as? [String: Any])
    }

    private func results(of log: [String: Any]) throws -> [[String: Any]] {
        try #require(try run(of: log)["results"] as? [[String: Any]])
    }

    private func physicalLocation(of log: [String: Any]) throws -> [String: Any] {
        let result = try #require(try results(of: log).first)
        let location = try #require((result["locations"] as? [[String: Any]])?.first)
        return try #require(location["physicalLocation"] as? [String: Any])
    }
}
