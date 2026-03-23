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

        let xcresultRaw = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["xcresulttool", "get", "test-results", "tests", "--path", xcresultPath],
            environment: nil,
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: timeout
        )

        if xcresultRaw.exitCode == 0 {
            switch XCResultParser().parse(xcresultRaw.output) {
            case .killed(let name):
                return .testsFailed(failingTest: name)
            case .crashed:
                return .crashed
            }
        }

        switch TestOutputParser().parse(output) {
        case .killed(let name):
            return .testsFailed(failingTest: name)
        case .crashed:
            return .crashed
        case .unviable:
            return .unviable
        }
    }
}
