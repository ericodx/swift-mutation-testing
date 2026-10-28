import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("RunConclusion timing")
struct RunConclusionTimingTests {
    private let summary = RunnerSummary(
        results: [], totalDuration: 10,
        phases: [PhaseTiming(phase: .mutants, start: Date(timeIntervalSince1970: 0), duration: 8)]
    )

    @Test("Given --timing, when the run concludes, then the table is printed after the summary")
    func printsTheTableWhenAsked() {
        let output = captureOutputSync {
            RunConclusion.reportTiming(summary, configuration: makeRunnerConfiguration(timing: true))
        }

        #expect(output.contains("Time by phase:"))
    }

    @Test("Given no --timing, when the run concludes, then nothing is printed")
    func printsNothingByDefault() {
        let output = captureOutputSync {
            RunConclusion.reportTiming(summary, configuration: makeRunnerConfiguration())
        }

        #expect(output.isEmpty)
    }

    @Test("Given --keep-logs, when the run concludes, then timing.json is written beside the mutant logs")
    func writesTimingJSONUnderKeepLogs() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let logs = dir.appendingPathComponent("logs")

        _ = captureOutputSync {
            RunConclusion.reportTiming(summary, configuration: makeRunnerConfiguration(keepLogsPath: logs.path))
        }

        let data = try Data(contentsOf: logs.appendingPathComponent(MutantLogWriter.timingFileName))
        let document = try JSONDecoder.timing.decode(TimingReporter.Document.self, from: data)
        #expect(document.totalDuration == 10)
        #expect(document.phases.map(\.phase) == [.mutants])
    }

    @Test("Given no phases, when the run concludes, then neither the table nor the file is produced")
    func nothingWithoutPhases() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let logs = dir.appendingPathComponent("logs")

        let output = captureOutputSync {
            RunConclusion.reportTiming(
                RunnerSummary(results: [], totalDuration: 10),
                configuration: makeRunnerConfiguration(keepLogsPath: logs.path, timing: true)
            )
        }

        #expect(output.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: logs.path))
    }
}

extension JSONDecoder {
    fileprivate static var timing: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
