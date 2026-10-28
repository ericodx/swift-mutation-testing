import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("PhaseTimings")
struct PhaseTimingsTests {
    @Test("Given a start and an end, when recorded, then the entry holds the phase and the time between them")
    func recordsTheTimeBetweenStartAndEnd() async {
        let timings = PhaseTimings()
        let start = Date(timeIntervalSince1970: 100)

        await timings.record(.schemaBuild, start: start, end: Date(timeIntervalSince1970: 120.5))

        let entries = await timings.entries
        #expect(entries == [PhaseTiming(phase: .schemaBuild, start: start, duration: 20.5)])
    }

    @Test("Given work that returns, when measured, then its value comes back and the phase is recorded")
    func measureReturnsTheValueAndRecords() async throws {
        let timings = PhaseTimings()

        let value = try await PhaseTimings.measure(.workers, in: timings) { 42 }

        let entries = await timings.entries
        #expect(value == 42)
        #expect(entries.map(\.phase) == [.workers])
        #expect(entries[0].duration >= 0)
    }

    @Test("Given work that throws, when measured, then the error propagates and the phase is still recorded")
    func measureRecordsWhenTheWorkThrows() async {
        struct Failure: Error {}
        let timings = PhaseTimings()

        await #expect(throws: Failure.self) {
            try await PhaseTimings.measure(.baseline, in: timings) { throw Failure() }
        }

        #expect(await timings.entries.map(\.phase) == [.baseline])
    }

    @Test("Given no timings, when measured, then the work still runs")
    func measureWithoutTimingsRunsTheWork() async throws {
        let value = try await PhaseTimings.measure(.sandbox, in: nil) { "done" }

        #expect(value == "done")
    }

    @Test("Given the same phase recorded twice, when read, then both entries are kept in order")
    func keepsRepeatedPhases() async {
        let timings = PhaseTimings()
        let first = Date(timeIntervalSince1970: 1)
        let second = Date(timeIntervalSince1970: 5)

        await timings.record(.schemaNarrowing, start: first, end: Date(timeIntervalSince1970: 3))
        await timings.record(.schemaNarrowing, start: second, end: Date(timeIntervalSince1970: 9))

        let entries = await timings.entries
        #expect(entries.map(\.duration) == [2, 4])
    }
}
