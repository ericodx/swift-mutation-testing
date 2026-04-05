import Foundation

struct XcodeProcessLauncher: Sendable, ProcessLaunching {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        try await makeRunner().launch(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        try await makeRunner().launchCapturing(request)
    }

    private func makeRunner() -> ProcessRunner {
        ProcessRunner(
            onTimeout: { pid in
                guard pid > 0 else { return }
                kill(-pid, SIGTERM)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    kill(-pid, SIGKILL)
                }
            }
        )
    }
}
