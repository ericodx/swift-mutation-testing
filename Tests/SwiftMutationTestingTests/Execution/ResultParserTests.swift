import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ResultParser")
struct ResultParserTests {
    @Test("Given exit code minus one, when parsed, then returns timedOut")
    func exitCodeMinusOneReturnsTimedOut() async throws {
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 0))

        let outcome = try await parser.parse(
            exitCode: -1,
            output: "",
            xcresultPath: "/tmp/test.xcresult",
            timeout: 60
        )

        #expect(outcome == .timedOut)
    }

    @Test("Given exit code zero, when parsed, then returns testsSucceeded")
    func exitCodeZeroReturnsTestsSucceeded() async throws {
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 0))

        let outcome = try await parser.parse(
            exitCode: 0,
            output: "",
            xcresultPath: "/tmp/test.xcresult",
            timeout: 60
        )

        #expect(outcome == .testsSucceeded)
    }

    @Test("Given failing stdout with test name, when parsed, then returns testsFailed without calling xcresulttool")
    func stdoutWithTestNameReturnsKilled() async throws {
        let output = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 1))

        let outcome = try await parser.parse(
            exitCode: 1,
            output: output,
            xcresultPath: "/tmp/test.xcresult",
            timeout: 60
        )

        #expect(outcome == .testsFailed(failingTest: "MySuite.myTest"))
    }

    @Test("Given empty stdout and xcresulttool returns valid JSON, when parsed, then returns testsFailed")
    func xcresultFallbackReturnsKilledWhenJSONValid() async throws {
        let xcresultJSON = """
            {
              "issues": {
                "testFailureSummaries": {
                  "_values": [{"testCaseName": {"_value": "Suite.test()"}}]
                }
              }
            }
            """
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 0, output: xcresultJSON))

        let outcome = try await parser.parse(
            exitCode: 1,
            output: "",
            xcresultPath: "/tmp/test.xcresult",
            timeout: 60
        )

        #expect(outcome == .testsFailed(failingTest: "Suite.test()"))
    }

    @Test("Given empty stdout and xcresulttool fails, when parsed, then returns unviable")
    func xcresultFallbackReturnsUnviableWhenToolFails() async throws {
        let parser = ResultParser(launcher: MockProcessLauncher(exitCode: 1))

        let outcome = try await parser.parse(
            exitCode: 1,
            output: "",
            xcresultPath: "/tmp/test.xcresult",
            timeout: 60
        )

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
