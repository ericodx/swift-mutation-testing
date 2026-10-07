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

    @Test(
        "Given output carrying a single test-run marker, when parsed, then returns crashed",
        arguments: [
            "◇ Suite \"Parsing\" started.\nsome other output",
            "✔ Test run with 3 tests in 1 suite passed after 0.002 seconds.",
            "Executed 0 tests, with 0 failures",
            "Test Suite 'All tests' started",
        ]
    )
    func eachTestRunMarkerAloneIsACrash(output: String) {
        #expect(TestOutputParser().parse(output) == .crashed)
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

    @Test("Given a test name mentioning a crash marker before a failing test, when parsed, then the test is named")
    func testNameMentioningACrashMarkerDoesNotHideTheFailingTest() {
        let output = """
            ◇ Test "Given output with EXC_BAD_INSTRUCTION, when parsed, then returns crashed" started.
            ◇ Test case passing 1 argument line → "Fatal error: unexpectedly found nil" started.
            ✘ Test "Given a body, when walked, then its shape is known" recorded an issue at A.swift:3:9: Expectation failed
            """

        let result = TestOutputParser().parse(output)

        #expect(result == .killed(by: "Given a body, when walked, then its shape is known"))
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

    // MARK: - Swift Testing shapes captured from a real run

    @Test(
        "Given a Swift Testing line naming an individual failing test, when parsed, then returns killed with that name",
        arguments: [
            (
                "✘ Test \"a check\" recorded an issue at F.swift:1:1: Expectation failed: a == b",
                "a check"
            ),
            (
                "✘ Test \"a check\" failed after 0.001 seconds with 1 issue.",
                "a check"
            ),
            (
                "✘ Test \"a check\" with 2 test cases failed after 0.001 seconds with 2 issues.",
                "a check"
            ),
            (
                "✘ Test \"a check\" recorded an issue with 1 argument value → 1 at F.swift:1:1: Expectation failed: a == b",
                "a check"
            ),
            (
                "✘ Test aCheck() recorded an issue at F.swift:1:1: Expectation failed: a == b",
                "aCheck()"
            ),
            (
                "✘ Test aCheck() failed after 0.001 seconds with 1 issue.",
                "aCheck()"
            ),
            (
                "✘ Test aCheck(value:) with 2 test cases failed after 0.001 seconds with 2 issues.",
                "aCheck(value:)"
            ),
        ]
    )
    func parsesIndividualSwiftTestingFailureShapes(line: String, expected: String) {
        let result = TestOutputParser().parse(line)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == expected)
    }

    @Test(
        "Given a Swift Testing line that is not an individual failure, when parsed, then no test is named",
        arguments: [
            "◇ Test \"a check\" started.",
            "◇ Test aCheck() started.",
            "◇ Test case passing 1 argument value → 1 to \"a check\" started.",
            "✔ Test \"a check\" passed after 0.001 seconds.",
            "✔ Test \"Given a failed login, when retried, then it passes\" passed after 0.001 seconds.",
            "━ Test \"a check\" recorded a known issue at F.swift:1:1: Expectation failed: a == b",
            "━ Test \"a check\" passed after 0.001 seconds with 1 known issue.",
            "✘ Suite \"a suite\" failed after 0.788 seconds with 16 issues.",
            "✘ Test run with 944 tests in 91 suites failed after 0.927 seconds with 16 issues.",
        ]
    )
    func doesNotNameATestForNonFailureLines(line: String) {
        #expect(TestOutputParser().failingTests(in: line).isEmpty)
    }

    @Test("Given a captured Swift Testing run, when parsed, then the mutant is killed rather than crashed")
    func parsesCapturedSwiftTestingRunAsKilled() throws {
        let output = try loadTestFixture("spm_swift_testing_failures")
        let result = TestOutputParser().parse(output)

        guard case .killed = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
    }

    @Test("Given a captured Swift Testing run, when failingTests called, then every failing test is named once")
    func failingTestsNamesEveryFailureInCapturedRun() throws {
        let output = try loadTestFixture("spm_swift_testing_failures")

        #expect(
            TestOutputParser().failingTests(in: output) == [
                "Given a display name, when it fails, then this shape is printed",
                "Parameterized",
                "unnamedParameterized(value:)",
                "unnamedFailure()",
                "Throwing test",
            ]
        )
    }

    @Test("Given output with no failures, when failingTests called, then returns empty")
    func failingTestsReturnsEmptyWithoutFailures() {
        let output = "Test Suite 'All tests' started\nExecuted 3 tests, with 0 failures"

        #expect(TestOutputParser().failingTests(in: output).isEmpty)
    }

    @Test("Given an XCTest line whose markers are out of order, when parsed, then no test is named")
    func xctestMarkersOutOfOrderNameNothing() {
        let line = "]' failed at some point, then Test Case '-["

        #expect(TestOutputParser().failingTests(in: line).isEmpty)
    }

    @Test("Given an XCTest line naming a single token, when parsed, then no test is named")
    func xctestFailureWithoutASuiteAndTestNameNamesNothing() {
        let line = "Test Case '-[OnlyOneToken]' failed (0.001 seconds)."

        #expect(TestOutputParser().failingTests(in: line).isEmpty)
    }

    @Test("Given a Swift Testing line whose quoted name never closes, when parsed, then no test is named")
    func unterminatedQuotedNameNamesNothing() {
        let line = #"✘ Test "a name that never closes failed after 0.1 seconds."#

        #expect(TestOutputParser().failingTests(in: line).isEmpty)
    }

    @Test("Given a Swift Testing line that ends at the test name, when parsed, then no test is named")
    func aLineThatEndsAtTheTestNameNamesNothing() {
        #expect(TestOutputParser().failingTests(in: "✘ Test aCheck()").isEmpty)
    }

    @Test(
        "Given a line that names a failure, when matched against the stop rule, then it stops the run",
        arguments: [
            "Test Case '-[CalculatorTests testAddition]' failed (0.002 seconds).",
            #"✘ Test "a check" recorded an issue at File.swift:3:9: Expectation failed"#,
            #"✘ Test "a check" failed after 0.001 seconds with 1 issue."#,
        ]
    )
    func aFailureLineStopsTheRun(line: String) {
        #expect(OutputStopRule.firstTestFailure.matches(line))
    }

    @Test(
        "Given a line that is not a failure, when matched against the stop rule, then the run goes on",
        arguments: [
            "Test Case '-[CalculatorTests testAddition]' passed (0.002 seconds).",
            #"✘ Test "a check" recorded a known issue at File.swift:3:9"#,
            "✔ Test run with 944 tests in 91 suites passed after 14.093 seconds.",
            "Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds",
            #"◇ Test case passing 1 argument l → "✘ Test "a" recorded an issue at F.swift:3:9" to "t" started."#,
            #"◇ Test case passing 1 argument l → "✘ Test "a" failed after 0.1 seconds with 1 issue." to "t" started."#,
            #"◇ Test case passing 1 argument l → "Test Case '-[A b]' failed (0.1 seconds)." to "t" started."#,
        ]
    )
    func aNonFailureLineLetsTheRunGoOn(line: String) {
        #expect(!OutputStopRule.firstTestFailure.matches(line))
    }

    @Test("Given an XCTest failure line indented by the tool that printed it, when parsed, then the test is named")
    func anIndentedXCTestFailureIsStillNamed() {
        #expect(TestOutputParser().failingTests(in: "    Test Case '-[A b]' failed (0.1 seconds).") == ["A.b"])
    }

    @Test("Given a line that quotes an XCTest failure after other text, when parsed, then no test is named")
    func aQuotedXCTestFailureNamesNothing() {
        let line = #"◇ Test case passing 1 argument l → "Test Case '-[A b]' failed (0.1 seconds)." to "t" started."#

        #expect(TestOutputParser().failingTests(in: line).isEmpty)
    }

    @Test("Given a quoted failure before a real one, when matched, then the rule stops at the real one")
    func aQuotedFailureDoesNotHideTheRealOne() {
        let output = """
            ◇ Test case passing 1 argument l → "✘ Test "a" recorded an issue at F.swift:3:9" to "t" started.
            ✔ Test "t" passed after 0.001 seconds.
            ✘ Test "another check" recorded an issue at File.swift:9:9: Expectation failed
            """

        #expect(OutputStopRule.firstTestFailure.matches(output))
        #expect(TestOutputParser().failingTests(in: output) == ["another check"])
    }
}
