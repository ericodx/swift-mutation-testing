import Testing

@testable import SwiftMutationTesting

@Suite("TestRunOutcome")
struct TestRunOutcomeTests {

    @Test("Given an outcome, when asked for its execution status, then each maps to the status it reports")
    func everyOutcomeMapsToItsStatus() {
        let failed = TestRunOutcome.testsFailed(failingTest: "SuiteTests.aCheck")

        #expect(failed.asExecutionStatus == .killed(by: "SuiteTests.aCheck"))
        #expect(TestRunOutcome.testsSucceeded.asExecutionStatus == .survived)
        #expect(TestRunOutcome.crashed.asExecutionStatus == .killedByCrash)
        #expect(TestRunOutcome.timedOut.asExecutionStatus == .timeout)
        #expect(TestRunOutcome.buildFailed.asExecutionStatus == .unviable)
        #expect(TestRunOutcome.unviable.asExecutionStatus == .unviable)
    }

    @Test("Given an outcome, when asked whether the tests detected the mutant, then a failure, a crash or a timeout did")
    func aFailureACrashOrATimeoutIsADetection() {
        #expect(TestRunOutcome.testsFailed(failingTest: "t").isDetected)
        #expect(TestRunOutcome.crashed.isDetected)
        #expect(TestRunOutcome.timedOut.isDetected)
        #expect(!TestRunOutcome.testsSucceeded.isDetected)
        #expect(!TestRunOutcome.buildFailed.isDetected)
        #expect(!TestRunOutcome.unviable.isDetected)
    }
}
