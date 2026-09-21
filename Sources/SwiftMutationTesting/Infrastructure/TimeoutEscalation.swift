import Foundation

/// The escalation from SIGTERM to SIGKILL for a run that timed out, tied to that run's lifetime.
///
/// A timed-out process is asked to stop, then given a grace period before being killed outright.
/// Almost always it stops within it, and waiting out the rest of the period is not merely pointless
/// but unsafe: by the time it elapses the next mutant is usually testing in the same sandbox, and a
/// pid recorded before the wait may by then belong to something else.
///
/// So the wait is cancelled the moment the process terminates, and the descendants it left behind
/// are killed there and then instead of on a timer (issue #69).
final class TimeoutEscalation: @unchecked Sendable {

    init(gracePeriod: Double = 5) {
        self.gracePeriod = gracePeriod
    }

    private let gracePeriod: Double
    private let lock = NSLock()
    private var pending: Task<Void, Never>?
    private var descendants: [Int32] = []

    /// Starts the grace period for `pid`, whose descendants were snapshotted while it was alive.
    func arm(pid: Int32, descendants: [Int32]) {
        let grace = gracePeriod

        lock.lock()
        self.descendants = descendants
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(grace))

            guard !Task.isCancelled else { return }

            kill(-pid, SIGKILL)
            self?.killSnapshottedDescendants()
        }
        lock.unlock()
    }

    /// Called when the process has terminated: the grace period no longer applies, but anything it
    /// spawned that outlived it still has to go.
    func processTerminated() {
        lock.lock()
        let task = pending
        pending = nil
        lock.unlock()

        task?.cancel()
        killSnapshottedDescendants()
    }

    // MARK: - Private

    private func killSnapshottedDescendants() {
        lock.lock()
        let targets = descendants
        descendants = []
        lock.unlock()

        for pid in targets {
            kill(pid, SIGKILL)
        }
    }
}
