import Foundation

final class TimeoutEscalation: @unchecked Sendable {

    init(gracePeriod: Double = 5) {
        self.gracePeriod = gracePeriod
    }

    private let gracePeriod: Double
    private let lock = NSLock()
    private var pending: Task<Void, Never>?
    private var descendants: [Int32] = []

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
