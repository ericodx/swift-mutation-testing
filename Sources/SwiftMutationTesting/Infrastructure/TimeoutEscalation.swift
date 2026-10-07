import Foundation

final class TimeoutEscalation: @unchecked Sendable {

    init(gracePeriod: Double = 5, kill: @escaping SystemCalls.Kill = Darwin.kill) {
        self.gracePeriod = gracePeriod
        self.kill = kill
    }

    private let gracePeriod: Double
    private let kill: SystemCalls.Kill
    private let lock = NSLock()
    private var pending: Task<Void, Never>?
    private var descendants: [Int32] = []
    private var terminated = false

    func arm(pid: Int32, descendants: [Int32]) {
        let grace = gracePeriod
        let kill = self.kill

        lock.lock()
        defer { lock.unlock() }

        guard !terminated else { return }

        pending?.cancel()
        self.descendants = descendants
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(grace))

            guard !Task.isCancelled else { return }

            _ = kill(-pid, SIGKILL)
            self?.killSnapshottedDescendants()
        }
    }

    @discardableResult
    func processTerminated() -> Bool {
        lock.lock()
        let task = pending
        pending = nil
        terminated = true
        lock.unlock()

        task?.cancel()
        killSnapshottedDescendants()
        return task != nil
    }

    // MARK: - Private

    private func killSnapshottedDescendants() {
        lock.lock()
        let targets = descendants
        descendants = []
        lock.unlock()

        for pid in targets {
            _ = kill(pid, SIGKILL)
        }
    }
}
