struct SPMResultParser: Sendable {
    func parse(exitCode: Int32, output: String) -> TestRunOutcome {
        if exitCode == -1 { return .timedOut }
        if exitCode == 0 { return .testsSucceeded }

        switch TestOutputParser().parse(output) {
        case .killed(let name): return .testsFailed(failingTest: name)
        case .crashed: return .crashed
        case .unviable: return output.isEmpty ? .crashed : .unviable
        }
    }
}
