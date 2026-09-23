import Foundation

struct SPMProcessLauncher: Sendable, ProcessLaunching {
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
        let escalation = TimeoutEscalation()

        return ProcessRunner(
            postTerminationCleanup: { pid in
                kill(-pid, SIGKILL)
                escalation.processTerminated()
            },
            onTimeout: { pid in
                guard pid > 0 else { return }

                escalation.arm(pid: pid, descendants: ProcessTree.descendants(of: pid))
                kill(-pid, SIGTERM)
            }
        )
    }
}
