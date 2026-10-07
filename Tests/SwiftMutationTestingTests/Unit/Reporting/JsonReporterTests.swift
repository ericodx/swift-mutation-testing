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
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24,
                    status: .killed(by: "Suite.test"))
            ],
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

    @Test("Given a run identity, when report called, then config carries the plan's hash, the shard and the tool")
    func theIdentityGoesInConfig() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let outputPath = dir.appendingPathComponent("mutation.json").path
        let summary = RunnerSummary(
            results: [makeExecutionResult(id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", status: .survived)],
            totalDuration: 1
        )

        try JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
            .report(summary, identity: RunIdentity(planSha256: "abc123", shard: Shard(index: 2, count: 3)))

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let config = json?["config"] as? [String: Any]
        #expect(config?["planSha256"] as? String == "abc123")
        #expect(config?["shard"] as? String == "2/3")
        #expect(config?["toolVersion"] as? String == Version.number)
    }

    @Test("Given no identity, when report called, then there is no config object")
    func noIdentityNoConfig() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let outputPath = dir.appendingPathComponent("mutation.json").path
        let summary = RunnerSummary(results: [], totalDuration: 1)

        try JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp").report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["config"] == nil)
    }

    @Test("Given a measured mutant, when report called, then its activation is in the report")
    func activationIsReported() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let outputPath = dir.appendingPathComponent("mutation.json").path
        let result = ExecutionResult(
            descriptor: makeMutantDescriptor(id: "1", filePath: "/abs/MyApp/Sources/Calc.swift"),
            status: .killed(by: "Suite.test"), testDuration: 1, activated: false
        )

        try JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
            .report(RunnerSummary(results: [result], totalDuration: 1))

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutant = (file?["mutants"] as? [[String: Any]])?.first
        #expect(mutant?["activated"] as? Bool == false)
    }

    @Test("Given a killed mutant, when report called, then status string is Killed")
    func killedMutantProducesKilledStatus() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .killed(by: "t"))
            ],
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
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .survived)
            ],
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
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24,
                    status: .killed(by: "MySuite.myTest"))
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]

        #expect(mutants?.first?["killedBy"] as? [String] == ["MySuite.myTest"])
    }

    @Test("Given a project root reached through a symlink, when report called, then keys are still relative")
    func aSymlinkedProjectRootStillGivesRelativeKeys() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let link = dir.appendingPathComponent("link")
        let real = dir.appendingPathComponent("real")
        let sources = real.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let resolvedFile = real.resolvingSymlinksInPath().appendingPathComponent("Sources/Calc.swift").path
        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: link.path)
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(id: "1", filePath: resolvedFile, line: 3, column: 24, status: .survived)
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        #expect(files?.keys.sorted() == ["/Sources/Calc.swift"])
    }

    @Test("Given a mutant killed by a crash, when report called, then it is Killed with crash as the reason")
    func crashedMutantIsKilledWithReason() throws {
        let mutant = try reportedMutant(status: .killedByCrash)

        #expect(mutant?["status"] as? String == "Killed")
        #expect(mutant?["statusReason"] as? String == "crash")
        #expect(mutant?["killedBy"] == nil)
    }

    @Test("Given a mutant killed by a test, when report called, then it carries no status reason")
    func killedMutantHasNoReason() throws {
        let mutant = try reportedMutant(status: .killed(by: "t"))

        #expect(mutant?["statusReason"] == nil)
    }

    @Test("Given a mutant, when report called, then its fingerprint is in the mutant entry")
    func mutantEntryCarriesTheFingerprint() throws {
        let mutant = try reportedMutant(status: .survived)

        #expect(mutant?["fingerprint"] as? String == "fingerprint")
    }

    @Test("Given an unviable mutant, when report called, then status string is CompileError")
    func unviableMutantIsCompileError() throws {
        let mutant = try reportedMutant(status: .unviable)

        #expect(mutant?["status"] as? String == "CompileError")
    }

    @Test("Given a survived mutant, when report called, then killedBy is nil")
    func survivedMutantHasNilKilledBy() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
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
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .survived)
            ],
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
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: .survived)
            ],
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

    @Test("Given original text with a multi-byte character, when report called, then the end column counts UTF-8 bytes")
    func endColumnCountsUTF8Bytes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let descriptor = makeMutantDescriptor(
            filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24,
            originalText: "\"café\"", mutatedText: "\"\""
        )

        try reporter.report(
            RunnerSummary(
                results: [ExecutionResult(descriptor: descriptor, status: .survived, testDuration: 0)],
                totalDuration: 0
            )
        )

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]
        let location = mutants?.first?["location"] as? [String: Any]
        let end = location?["end"] as? [String: Any]

        #expect(end?["column"] as? Int == 24 + 7)
    }

    @Test("Given a mutant whose tests took 1.2345 seconds, when report called, then its duration is 1235 milliseconds")
    func durationIsWrittenInMilliseconds() throws {
        let mutant = try reportedMutant(status: .killed(by: "t"), testDuration: 1.2345)

        #expect(mutant?["duration"] as? Int == 1235)
    }

    @Test("Given a mutant served from the cache, with no test duration, when report called, then it has no duration")
    func aCachedMutantHasNoDuration() throws {
        let mutant = try reportedMutant(status: .survived, testDuration: 0)

        #expect(mutant?["duration"] == nil)
    }

    private func reportedMutant(status: ExecutionStatus, testDuration: Double = 0) throws -> [String: Any]? {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("mutation.json").path
        let reporter = JsonReporter(outputPath: outputPath, projectRoot: "/abs/MyApp")
        let summary = RunnerSummary(
            results: [
                makeExecutionResult(
                    id: "1", filePath: "/abs/MyApp/Sources/Calc.swift", line: 3, column: 24, status: status,
                    testDuration: testDuration)
            ],
            totalDuration: 0
        )

        try reporter.report(summary)

        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: Any]
        let file = files?["/Sources/Calc.swift"] as? [String: Any]
        let mutants = file?["mutants"] as? [[String: Any]]
        return mutants?.first
    }
}
