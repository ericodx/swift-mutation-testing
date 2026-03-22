import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ResultParser")
struct ResultParserTests {
    private let xcresultJSON = """
        {
          "testNodes": [
            {
              "nodeType": "Test Suite",
              "name": "Suite",
              "result": "Failed",
              "children": [
                {
                  "nodeType": "Test Case",
                  "name": "test()",
                  "nodeIdentifier": "Suite/test()",
                  "result": "Failed"
                }
              ]
            }
          ]
        }
        """

    @Test("Given exit code minus one, when parsed, then returns timedOut")
    func exitCodeMinusOneReturnsTimedOut() async throws {
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 0))

        let outcome = try await parser.parse(
            exitCode: -1, output: "", xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .timedOut)
    }

    @Test("Given exit code zero, when parsed, then returns testsSucceeded")
    func exitCodeZeroReturnsTestsSucceeded() async throws {
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 0))

        let outcome = try await parser.parse(
            exitCode: 0, output: "", xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .testsSucceeded)
    }

    @Test("Given xcresulttool returns valid JSON with test name, when parsed, then returns testsFailed")
    func xcresultPrimaryReturnsKilledWhenJSONValid() async throws {
        let parser = ResultParser(
            launcher: MockProcessLauncher(
                exitCode: 1,
                responses: ["xcrun": (exitCode: 0, output: xcresultJSON)]
            )
        )

        let outcome = try await parser.parse(
            exitCode: 1, output: "", xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .testsFailed(failingTest: "Suite/test()"))
    }

    @Test("Given xcresulttool returns JSON with no test failures, when parsed, then returns crashed")
    func xcresultPrimaryReturnsCrashedWhenNoTestName() async throws {
        let parser = ResultParser(
            launcher: MockProcessLauncher(
                exitCode: 1,
                responses: ["xcrun": (exitCode: 0, output: "{}")]
            )
        )

        let outcome = try await parser.parse(
            exitCode: 1, output: "", xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .crashed)
    }

    @Test("Given xcresulttool fails and stdout has XCTest failure, when parsed, then returns testsFailed")
    func xcresultFailsFallsBackToStdoutKilled() async throws {
        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 1))

        let outcome = try await parser.parse(
            exitCode: 1, output: output, xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .testsFailed(failingTest: "MySuite.myTest"))
    }

    @Test("Given xcresulttool fails and stdout has test activity, when parsed, then returns crashed")
    func xcresultFailsFallsBackToStdoutCrashed() async throws {
        let output = "Testing started\nFatal error: unexpected"
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 1))

        let outcome = try await parser.parse(
            exitCode: 1, output: output, xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .crashed)
    }

    @Test("Given xcresulttool fails and stdout is empty, when parsed, then returns unviable")
    func xcresultFailsAndEmptyStdoutReturnsUnviable() async throws {
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 1))

        let outcome = try await parser.parse(
            exitCode: 1, output: "", xcresultPath: "/tmp/test.xcresult", timeout: 60)

        #expect(outcome == .unviable)
    }
}

extension TestRunOutcome: Equatable {
    public static func == (lhs: TestRunOutcome, rhs: TestRunOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.testsFailed(let lhsName), .testsFailed(let rhsName)): return lhsName == rhsName
        case (.testsSucceeded, .testsSucceeded): return true
        case (.crashed, .crashed): return true
        case (.timedOut, .timedOut): return true
        case (.buildFailed, .buildFailed): return true
        case (.unviable, .unviable): return true
        default: return false
        }
    }
}
