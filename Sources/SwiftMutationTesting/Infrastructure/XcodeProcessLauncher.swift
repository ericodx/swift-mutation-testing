import Foundation

struct XcodeProcessLauncher: Sendable, RunnerLaunching {
    static func terminate(
        pid: pid_t,
        escalation: TimeoutEscalation,
        kill: SystemCalls.Kill = Darwin.kill
    ) {
        guard pid > 0 else { return }

        _ = kill(-pid, SIGTERM)
        escalation.arm(pid: pid, descendants: [])
    }

    func makeRunner() -> ProcessRunner {
        let escalation = TimeoutEscalation()

        return ProcessRunner(
            postTerminationCleanup: { pid in
                if escalation.processTerminated() {
                    kill(-pid, SIGKILL)
                }
            },
            onTimeout: { pid in
                Self.terminate(pid: pid, escalation: escalation)
            }
        )
    }
}
