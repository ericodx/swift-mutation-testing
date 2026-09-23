struct SPMResultParser: Sendable {
    static let timedOutExitCode: Int32 = -1

    func parse(exitCode: Int32, output: String) -> TestRunOutcome {
        if exitCode == Self.timedOutExitCode { return .timedOut }
        if exitCode == 0 { return .testsSucceeded }

        switch TestOutputParser().parse(output) {
        case .killed(let name): return .testsFailed(failingTest: name)
        case .crashed: return .crashed
        case .unviable: return output.isEmpty ? .crashed : .unviable
        }
    }
}
