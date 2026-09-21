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

    /// A timed-out `swift test` is asked to stop, and anything it spawned that outlived the process
    /// group is killed with it.
    ///
    /// Those descendants are collected *before* the first signal, while the process that owns them
    /// is still alive to be traced back to — once it dies they are reparented and nothing connects
    /// them to it. Cleanup used to find them by searching every process on the machine for one
    /// whose arguments mentioned the sandbox, which cannot tell one mutant's run from another's
    /// when both run in the same sandbox: it killed the next mutant's test binary, and the
    /// truncated output was read as a crash (issue #69).
    ///
    /// `TimeoutEscalation` ties the SIGKILL that follows to this run's lifetime, so a process that
    /// stops when asked is cleaned up at once rather than on a timer that outlives it.
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
