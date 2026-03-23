enum TestRunOutcome: Sendable {
    case testsFailed(failingTest: String)
    case testsSucceeded
    case crashed
    case timedOut
    case buildFailed
    case unviable

    var asExecutionStatus: ExecutionStatus {
        switch self {
        case .testsFailed(let name): return .killed(by: name)
        case .testsSucceeded: return .survived
        case .crashed: return .killedByCrash
        case .timedOut: return .timeout
        case .buildFailed: return .unviable
        case .unviable: return .unviable
        }
    }
}
