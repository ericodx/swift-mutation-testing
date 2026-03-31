import Testing

@testable import SwiftMutationTesting

@Suite("SPMResultParser")
struct SPMResultParserTests {
    private let parser = SPMResultParser()

    @Test("Given exit code -1, when parse called, then returns timedOut")
    func exitCodeMinusOneReturnsTimedOut() {
        #expect(parser.parse(exitCode: -1, output: "") == .timedOut)
    }

    @Test("Given exit code 0, when parse called, then returns testsSucceeded")
    func exitCodeZeroReturnsTestsSucceeded() {
        #expect(parser.parse(exitCode: 0, output: "") == .testsSucceeded)
    }

    @Test("Given exit code 1 and Swift Testing failure in output, when parse called, then returns testsFailed")
    func swiftTestingFailureOutputReturnsTestsFailed() {
        let output = #"Test "myTest" failed after 0.001 seconds."#
        let result = parser.parse(exitCode: 1, output: output)
        #expect(result == .testsFailed(failingTest: "myTest"))
    }

    @Test("Given exit code 1 and XCTest failure in output, when parse called, then returns testsFailed")
    func xcTestFailureOutputReturnsTestsFailed() {
        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let result = parser.parse(exitCode: 1, output: output)
        #expect(result == .testsFailed(failingTest: "MySuite.myTest"))
    }

    @Test("Given exit code 1 and crash in output, when parse called, then returns crashed")
    func crashOutputReturnsCrashed() {
        let output = "Test run started.\nFatal error: something went wrong"
        let result = parser.parse(exitCode: 1, output: output)
        #expect(result == .crashed)
    }

    @Test("Given exit code 1 and no recognisable test output, when parse called, then returns unviable")
    func noTestOutputReturnsUnviable() {
        let result = parser.parse(exitCode: 1, output: "something unrelated")
        #expect(result == .unviable)
    }
}
