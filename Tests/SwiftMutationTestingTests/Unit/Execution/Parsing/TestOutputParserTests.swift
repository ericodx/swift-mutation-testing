import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestOutputParser")
struct TestOutputParserTests {
    @Test("Given XCTest failure line, when parsed, then returns killed with suite.test name")
    func parsesXCTestFailureLine() {
        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "MySuite.myTest")
    }

    @Test("Given Swift Testing failure line with checkmark prefix, when parsed, then returns killed with test name")
    func parsesSwiftTestingFailureLineWithPrefix() {
        let output = "✗ Test \"myTestFunction\" failed"
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "myTestFunction")
    }

    @Test("Given indented Swift Testing failure line from xcodebuild, when parsed, then returns killed with test name")
    func parsesIndentedSwiftTestingFailureLine() {
        let output = "    ✗ Test \"myTestFunction\" failed after 0.001 seconds"
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "myTestFunction")
    }

    @Test("Given Swift Testing failure line without prefix, when parsed, then returns killed with test name")
    func parsesSwiftTestingFailureLineWithoutPrefix() {
        let output = "Test \"myTestFunction\" failed after 0.001 seconds"
        let result = TestOutputParser().parse(output)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "myTestFunction")
    }

    @Test("Given output with fatal error, when parsed, then returns crashed")
    func parsesFatalErrorAsCrashed() {
        let output = "Fatal error: Unexpectedly found nil while unwrapping an Optional value"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given output with TEST FAILED but no test name, when parsed, then returns crashed")
    func parsesTestFailedWithoutNameAsCrashed() {
        let output = "** TEST FAILED **\nExecuted 0 tests"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given output with Testing started marker, when parsed, then returns crashed")
    func parsesTestingStartedAsCrashed() {
        let output = "Testing started\nsome other output"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given output with Test run started marker, when parsed, then returns crashed")
    func parsesTestRunStartedAsCrashed() {
        let output = "Test run started.\nsome other output"
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given empty output, when parsed, then returns unviable")
    func parsesEmptyOutputAsUnviable() {
        let result = TestOutputParser().parse("")

        #expect(result == .unviable)
    }

    @Test("Given SPM swift test output with fatal error, when parsed, then returns crashed")
    func parsesSPMFatalErrorCrash() throws {
        let output = try loadTestFixture("spm_xctest_fatal_error")
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given SPM swift test output with EXC_BAD_INSTRUCTION, when parsed, then returns crashed")
    func parsesSPMEXCBadInstructionCrash() throws {
        let output = try loadTestFixture("spm_xctest_exc_bad_instruction")
        let result = TestOutputParser().parse(output)

        #expect(result == .crashed)
    }

    @Test("Given several XCTest failures, when failingTests called, then returns all of them in order")
    func failingTestsReturnsEveryXCTestFailure() {
        let output = """
            Test Case '-[MySuite firstTest]' failed (0.001 seconds).
            Test Case '-[MySuite secondTest]' passed (0.001 seconds).
            Test Case '-[OtherSuite thirdTest]' failed (0.002 seconds).
            """

        #expect(TestOutputParser().failingTests(in: output) == ["MySuite.firstTest", "OtherSuite.thirdTest"])
    }

    @Test("Given the same failure reported twice, when failingTests called, then it appears once")
    func failingTestsDeduplicates() {
        let output = """
            Test Case '-[MySuite myTest]' failed (0.001 seconds).
            Test Case '-[MySuite myTest]' failed (0.001 seconds).
            """

        #expect(TestOutputParser().failingTests(in: output) == ["MySuite.myTest"])
    }

    @Test("Given Swift Testing failures, when failingTests called, then returns the test names")
    func failingTestsReturnsSwiftTestingFailures() {
        let output = """
            ✘ Test "a first check" failed after 0.001 seconds.
            ✘ Test "a second check" failed after 0.002 seconds.
            """

        #expect(TestOutputParser().failingTests(in: output) == ["a first check", "a second check"])
    }

    @Test("Given output with no failures, when failingTests called, then returns empty")
    func failingTestsReturnsEmptyWithoutFailures() {
        let output = "Test Suite 'All tests' started\nExecuted 3 tests, with 0 failures"

        #expect(TestOutputParser().failingTests(in: output).isEmpty)
    }
}
