import Foundation

struct SPMProcessLauncher: Sendable, RunnerLaunching {
    static func terminate(
        pid: pid_t,
        escalation: TimeoutEscalation,
        kill: SystemCalls.Kill = Darwin.kill
    ) {
        guard pid > 0 else { return }

        _ = kill(-pid, SIGSTOP)
        let descendants = ProcessTree.descendants(of: pid)
        escalation.arm(pid: pid, descendants: descendants)

        for descendant in descendants {
            _ = kill(descendant, SIGKILL)
        }
        _ = kill(-pid, SIGKILL)
    }

    func makeRunner() -> ProcessRunner {
        let escalation = TimeoutEscalation()

        return ProcessRunner(
            postTerminationCleanup: { pid in
                kill(-pid, SIGKILL)
                escalation.processTerminated()
            },
            onTimeout: { pid in
                Self.terminate(pid: pid, escalation: escalation)
            }
        )
    }
}
