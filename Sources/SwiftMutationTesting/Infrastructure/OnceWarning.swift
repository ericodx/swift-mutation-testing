import Synchronization

final class OnceWarning: Sendable {

    init(warn: @escaping @Sendable (String) -> Void = StandardError.write) {
        self.warn = warn
    }

    func callAsFunction(_ message: @autoclosure () -> String) {
        guard !shown.exchange(true, ordering: .relaxed) else { return }
        warn(message())
    }

    // MARK: - Private

    private let warn: @Sendable (String) -> Void
    private let shown = Atomic<Bool>(false)
}
