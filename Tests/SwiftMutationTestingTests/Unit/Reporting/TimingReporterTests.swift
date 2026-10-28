import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TimingReporter")
struct TimingReporterTests {
    private func timing(_ phase: RunPhase, _ duration: Double) -> PhaseTiming {
        PhaseTiming(phase: phase, start: Date(timeIntervalSince1970: 0), duration: duration)
    }

    @Test("Given no phases, when formatted, then there is no table")
    func noPhasesMeansNoTable() {
        let summary = RunnerSummary(results: [], totalDuration: 10)

        #expect(TimingReporter().format(summary) == nil)
        #expect(TimingReporter().lines(for: summary).isEmpty)
    }

    @Test("Given phases, when listed, then each phase is one line in run order with its entries summed and counted")
    func sumsAndCountsEachPhase() {
        let summary = RunnerSummary(
            results: [], totalDuration: 100,
            phases: [
                timing(.schemaNarrowing, 6), timing(.schemaBuild, 20), timing(.schemaNarrowing, 7),
                timing(.mutants, 50),
            ]
        )

        let lines = TimingReporter().lines(for: summary)

        #expect(
            lines == [
                TimingReporter.Line(label: "Schema build", duration: 20, count: 1),
                TimingReporter.Line(label: "Schema narrowing", duration: 13, count: 2),
                TimingReporter.Line(label: "Mutants", duration: 50, count: 1),
                TimingReporter.Line(label: "Other", duration: 17, count: 1),
            ]
        )
    }

    @Test("Given discovery, when the rest is computed, then discovery is left out, since it precedes the total")
    func discoveryIsOutsideTheTotal() {
        let summary = RunnerSummary(
            results: [], totalDuration: 30, phases: [timing(.discovery, 5), timing(.mutants, 28)]
        )

        let lines = TimingReporter().lines(for: summary)

        #expect(lines.first == TimingReporter.Line(label: "Discovery", duration: 5, count: 1))
        #expect(lines.last == TimingReporter.Line(label: "Other", duration: 2, count: 1))
    }

    @Test("Given phases longer than the total, when the rest is computed, then it is never negative")
    func restIsNeverNegative() {
        let summary = RunnerSummary(results: [], totalDuration: 1, phases: [timing(.mutants, 3)])

        #expect(TimingReporter().lines(for: summary).last?.duration == 0)
    }

    @Test("Given phases, when formatted, then the table aligns the labels and marks repeated phases")
    func formatsATable() throws {
        let summary = RunnerSummary(
            results: [], totalDuration: 60.25,
            phases: [timing(.schemaBuild, 20), timing(.schemaNarrowing, 6.5), timing(.schemaNarrowing, 7)]
        )

        let output = try #require(TimingReporter().format(summary))

        #expect(
            output == """

                Time by phase:
                  Schema build          20.0s
                  Schema narrowing      13.5s   2×
                  Other                 26.8s
                """
        )
    }

    @Test("Given phases, when encoded, then the JSON holds the total and every entry with its phase name")
    func encodesEveryEntry() throws {
        let summary = RunnerSummary(
            results: [], totalDuration: 42, phases: [timing(.sandbox, 0.5), timing(.teardown, 1)]
        )

        let data = try TimingReporter().json(summary)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let phases = try #require(json["phases"] as? [[String: Any]])

        #expect(json["totalDuration"] as? Double == 42)
        #expect(phases.map { $0["phase"] as? String } == ["sandbox", "teardown"])
        #expect(phases.map { $0["duration"] as? Double } == [0.5, 1])
        #expect(phases[0]["start"] as? String == "1970-01-01T00:00:00Z")
    }

    @Test("Given a table, when reported, then it goes to stdout")
    func reportsToStandardOutput() {
        let summary = RunnerSummary(results: [], totalDuration: 5, phases: [timing(.mutants, 4)])

        let output = captureOutputSync { TimingReporter().report(summary) }

        #expect(output.contains("Time by phase:"))
        #expect(output.contains("Mutants"))
    }
}
