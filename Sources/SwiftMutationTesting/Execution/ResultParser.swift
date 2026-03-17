import Foundation

struct ResultParser: Sendable {
    let launcher: any ProcessLaunching

    func parse(
        exitCode: Int32,
        output: String,
        xcresultPath: String,
        timeout: Double
    ) async throws -> TestRunOutcome {
        if exitCode == -1 { return .timedOut }
        if exitCode == 0 { return .testsSucceeded }

        let stdout = TestOutputParser().parse(output)

        switch stdout {
        case .killed(let name):
            return .testsFailed(failingTest: name)

        case .crashed, .unviable:
            let xcresult = try await parseXCResult(at: xcresultPath, timeout: timeout)

            switch xcresult {
            case .killed(let name):
                return .testsFailed(failingTest: name)
            case .crashed, nil:
                if case .unviable = stdout { return .unviable }
                return .crashed
            }
        }
    }

    private func parseXCResult(
        at path: String,
        timeout: Double
    ) async throws -> XCResultParser.Result? {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["xcresulttool", "get", "--path", path, "--format", "json"],
            environment: nil,
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: timeout
        )

        guard result.exitCode == 0 else { return nil }

        return XCResultParser().parse(result.output)
    }
}
