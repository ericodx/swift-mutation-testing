import Foundation

struct XcodeProcessLauncher: Sendable, RunnerLaunching {
    private static let detachedSnapshotAttempts = 5

    static func terminate(
        pid: pid_t,
        escalation: TimeoutEscalation,
        kill: SystemCalls.Kill = Darwin.kill,
        detachedDescendants: (pid_t) -> [Int32] = { ProcessTree.detachedDescendants(of: $0) }
    ) {
        guard pid > 0 else { return }

        for descendant in stopDetachedDescendants(of: pid, kill: kill, detachedDescendants: detachedDescendants) {
            _ = kill(descendant, SIGKILL)
        }
        _ = kill(-pid, SIGTERM)
        escalation.arm(pid: pid, descendants: [])
    }

    private static func stopDetachedDescendants(
        of pid: pid_t,
        kill: SystemCalls.Kill,
        detachedDescendants: (pid_t) -> [Int32]
    ) -> [Int32] {
        var stopped: [Int32] = []
        for _ in 0 ..< detachedSnapshotAttempts {
            let found = detachedDescendants(pid).filter { !stopped.contains($0) }
            guard !found.isEmpty else { break }
            for descendant in found {
                _ = kill(descendant, SIGSTOP)
            }
            stopped += found
        }
        return stopped
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
