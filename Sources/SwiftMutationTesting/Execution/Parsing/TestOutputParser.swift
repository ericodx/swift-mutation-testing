struct TestOutputParser: Sendable {
    enum Result: Sendable {
        case killed(by: String)
        case crashed
        case unviable
    }

    func parse(_ output: String) -> Result {
        var hasTestOutput = false

        for line in output.components(separatedBy: "\n") {
            if let name = extractFailingTest(from: line) {
                return .killed(by: name)
            }

            if line.contains("Fatal error") || line.contains("EXC_BAD_INSTRUCTION") {
                return .crashed
            }

            if line.contains("Test Suite")
                || line.contains("Test run started")
                || line.contains("Testing started")
                || line.contains("** TEST FAILED **")
                || line.contains("Executed")
                || line.contains("◇ Suite")
                || line.contains("Test run with")
            {
                hasTestOutput = true
            }
        }

        return hasTestOutput ? .crashed : .unviable
    }

    private func extractFailingTest(from line: String) -> String? {
        if let name = extractXCTestFailure(from: line) {
            return name
        }

        if let name = extractSwiftTestingFailure(from: line) {
            return name
        }

        return nil
    }

    private func extractXCTestFailure(from line: String) -> String? {
        let prefix = "Test Case '-["
        let suffix = "]' failed"

        guard line.contains(prefix), line.contains(suffix) else { return nil }

        guard
            let start = line.range(of: prefix)?.upperBound,
            let end = line.range(of: suffix)?.lowerBound,
            start < end
        else { return nil }

        let inner = String(line[start ..< end])
        let parts = inner.split(separator: " ", maxSplits: 1)

        guard parts.count == 2 else { return nil }

        return "\(parts[0]).\(parts[1])"
    }

    private func extractSwiftTestingFailure(from line: String) -> String? {
        guard line.contains("Test \""), line.contains("\" failed") else { return nil }

        guard
            let start = line.range(of: "Test \"")?.upperBound,
            let end = line.range(of: "\" failed")?.lowerBound,
            start < end
        else { return nil }

        return String(line[start ..< end])
    }
}
