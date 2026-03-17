enum TestRunOutcome: Sendable {
    case testsFailed(failingTest: String)
    case testsSucceeded
    case crashed
    case timedOut
    case buildFailed
    case unviable
}
