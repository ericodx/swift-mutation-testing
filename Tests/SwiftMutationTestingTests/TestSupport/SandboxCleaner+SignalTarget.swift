@testable import SwiftMutationTesting

extension SandboxCleaner {
    static func withSignalTarget<T>(_ target: SignalTarget, _ body: () throws -> T) rethrows -> T {
        let previous = signalTarget.withLock { current in
            defer { current = target }
            return current
        }
        defer { signalTarget.withLock { $0 = previous } }
        return try body()
    }
}
