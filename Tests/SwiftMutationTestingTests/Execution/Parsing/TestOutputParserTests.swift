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
}

extension TestOutputParser.Result: Equatable {
    public static func == (lhs: TestOutputParser.Result, rhs: TestOutputParser.Result) -> Bool {
        switch (lhs, rhs) {
        case (.killed(let lhsName), .killed(let rhsName)): return lhsName == rhsName
        case (.crashed, .crashed): return true
        case (.unviable, .unviable): return true
        default: return false
        }
    }
}
