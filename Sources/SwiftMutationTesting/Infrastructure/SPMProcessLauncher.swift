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

    /// A timed-out `swift test` is given SIGTERM, then SIGKILL five seconds later, and anything it
    /// spawned that outlived the process group is killed with it.
    ///
    /// Those descendants are collected *before* the first signal, while the process that owns them
    /// is still alive to be traced back to. Five seconds later the run that timed out may be long
    /// finished and the next mutant already testing in the same sandbox, so cleanup has to know
    /// which processes were its own — it used to kill whichever ones mentioned the sandbox, which
    /// meant killing the next mutant's test binary and reporting that mutant as a crash (issue #69).
    private func makeRunner() -> ProcessRunner {
        ProcessRunner(
            postTerminationCleanup: { pid in
                kill(-pid, SIGKILL)
            },
            onTimeout: { pid in
                guard pid > 0 else { return }

                let descendants = ProcessTree.descendants(of: pid)
                kill(-pid, SIGTERM)

                Task {
                    try? await Task.sleep(for: .seconds(5))
                    kill(-pid, SIGKILL)
                    for descendant in descendants {
                        kill(descendant, SIGKILL)
                    }
                }
            }
        )
    }
}
