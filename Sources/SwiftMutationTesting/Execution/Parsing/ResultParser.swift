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

        let xcresultRaw = try await launcher.launchCapturing(testsRequest(xcresultPath: xcresultPath, timeout: timeout))

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

    func testIdentifiers(xcresultPath: String, timeout: Double) async -> [String] {
        let request = testsRequest(xcresultPath: xcresultPath, timeout: timeout)
        guard let listed = try? await launcher.launchCapturing(request), listed.exitCode == 0 else { return [] }

        return XCResultParser().testIdentifiers(in: listed.output)
    }

    // MARK: - Private

    private func testsRequest(xcresultPath: String, timeout: Double) -> ProcessRequest {
        ProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "xcresulttool", "get", "test-results",
                "tests", "--path", xcresultPath,
            ],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: timeout
        ).discardingStandardError()
    }
}
