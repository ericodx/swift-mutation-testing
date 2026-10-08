import Foundation

enum ToolRequests {
    static let noTestDiagnostics = ["-collect-test-diagnostics", "never"]

    static func swiftBuildTests(in sandbox: Sandbox, timeout: Double) -> ProcessRequest {
        request("/usr/bin/swift", ["build", "--build-tests"], in: sandbox, timeout: timeout)
    }

    static func swiftTest(
        in sandbox: Sandbox, filter: String?, environment: [String: String], timeout: Double
    ) -> ProcessRequest {
        let filterArguments = filter.map { ["--filter", $0] } ?? []
        return request(
            "/usr/bin/swift", ["test", "--skip-build"] + filterArguments, in: sandbox, environment: environment,
            timeout: timeout
        )
    }

    static func buildForTesting(
        in sandbox: Sandbox, scheme: String, destination: String, container: XcodeContainer?, timeout: Double
    ) -> ProcessRequest {
        let arguments = [
            "build-for-testing",
            "-scheme", scheme,
            "-destination", destination,
            "-derivedDataPath", derivedDataPath(in: sandbox),
        ]
        return xcodebuild(arguments + (container?.arguments ?? []), in: sandbox, timeout: timeout)
    }

    static func xcodebuild(
        _ arguments: [String], in sandbox: Sandbox, environment: [String: String] = [:], timeout: Double
    ) -> ProcessRequest {
        request("/usr/bin/xcodebuild", arguments, in: sandbox, environment: environment, timeout: timeout)
    }

    static func derivedDataPath(in sandbox: Sandbox) -> String {
        sandbox.rootURL.appendingPathComponent(".xmr-derived-data").path
    }

    // MARK: - Private

    private static func request(
        _ executable: String, _ arguments: [String], in sandbox: Sandbox, environment: [String: String] = [:],
        timeout: Double
    ) -> ProcessRequest {
        ProcessRequest(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: environment,
            workingDirectoryURL: sandbox.rootURL,
            timeout: timeout
        )
    }
}
