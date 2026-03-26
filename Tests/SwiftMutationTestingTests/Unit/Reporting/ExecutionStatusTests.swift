import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ExecutionStatus")
struct ExecutionStatusTests {
    @Test("Given killed status, when mutationReportStatus called, then returns Killed")
    func killedReturnsKilled() {
        #expect(ExecutionStatus.killed(by: "t").mutationReportStatus == "Killed")
    }

    @Test("Given killedByCrash status, when mutationReportStatus called, then returns Crash")
    func killedByCrashReturnsCrash() {
        #expect(ExecutionStatus.killedByCrash.mutationReportStatus == "Crash")
    }

    @Test("Given survived status, when mutationReportStatus called, then returns Survived")
    func survivedReturnsSurvived() {
        #expect(ExecutionStatus.survived.mutationReportStatus == "Survived")
    }

    @Test("Given unviable status, when mutationReportStatus called, then returns Unviable")
    func unviableReturnsUnviable() {
        #expect(ExecutionStatus.unviable.mutationReportStatus == "Unviable")
    }

    @Test("Given timeout status, when mutationReportStatus called, then returns Timeout")
    func timeoutReturnsTimeout() {
        #expect(ExecutionStatus.timeout.mutationReportStatus == "Timeout")
    }

    @Test("Given noCoverage status, when mutationReportStatus called, then returns NoCoverage")
    func noCoverageReturnsNoCoverage() {
        #expect(ExecutionStatus.noCoverage.mutationReportStatus == "NoCoverage")
    }

    @Test("Given killed status, when progressIcon called, then returns check mark")
    func killedProgressIconIsCheckMark() {
        #expect(ExecutionStatus.killed(by: "t").progressIcon == "✓")
    }

    @Test("Given killedByCrash status, when progressIcon called, then returns check mark")
    func killedByCrashProgressIconIsCheckMark() {
        #expect(ExecutionStatus.killedByCrash.progressIcon == "✓")
    }

    @Test("Given survived status, when progressIcon called, then returns cross")
    func survivedProgressIconIsCross() {
        #expect(ExecutionStatus.survived.progressIcon == "✗")
    }

    @Test("Given unviable status, when progressIcon called, then returns warning")
    func unviableProgressIconIsWarning() {
        #expect(ExecutionStatus.unviable.progressIcon == "⚠")
    }

    @Test("Given timeout status, when progressIcon called, then returns clock")
    func timeoutProgressIconIsClock() {
        #expect(ExecutionStatus.timeout.progressIcon == "⏱")
    }

    @Test("Given noCoverage status, when progressIcon called, then returns dash")
    func noCoverageProgressIconIsDash() {
        #expect(ExecutionStatus.noCoverage.progressIcon == "–")
    }

    @Test("Given JSON with unknown kind, when decoded, then throws DecodingError")
    func decodingUnknownKindThrows() {
        let json = Data(#"{"kind":"unknown_status"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ExecutionStatus.self, from: json)
        }
    }
}
