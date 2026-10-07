import Foundation
import Synchronization

private let signalTarget = Mutex(SandboxCleaner.SignalTarget.process)
private let signalSources = Mutex<[any DispatchSourceSignal]>([])

private func catchSignal(_: Int32) {}

private func handleSignal() {
    signalTarget.withLock {
        SandboxCleaner.terminate(registry: $0.registry, processGroups: $0.processGroups, exit: $0.exit)
    }
}

enum SandboxCleaner {

    struct SignalTarget: Sendable {
        static let process = SignalTarget(registry: .shared, processGroups: .shared, exit: { _exit($0) })

        let registry: SandboxRegistry
        let processGroups: ProcessGroupRegistry
        let exit: @Sendable (Int32) -> Void
    }

    static func withSignalTarget<T>(_ target: SignalTarget, _ body: () throws -> T) rethrows -> T {
        let previous = signalTarget.withLock { current in
            defer { current = target }
            return current
        }
        defer { signalTarget.withLock { $0 = previous } }
        return try body()
    }

    static func cleanupActiveSandbox(in registry: SandboxRegistry = .shared) {
        registry.cleanup()
    }

    static func terminate(
        registry: SandboxRegistry = .shared,
        processGroups: ProcessGroupRegistry = .shared,
        exit: (Int32) -> Void = SignalTarget.process.exit
    ) {
        processGroups.killAll()
        registry.cleanup()
        exit(1)
    }

    static func removeOrphaned(in directory: URL = SandboxName.directory) {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return }

        for url in contents where url.lastPathComponent.hasPrefix(SandboxName.prefix) {
            guard !SandboxName.isOwnerAlive(of: url.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func register(_ sandbox: Sandbox, in registry: SandboxRegistry = .shared) {
        registry.register(sandbox)
    }

    static func deregister(in registry: SandboxRegistry = .shared) {
        registry.deregister()
    }

    static let handledSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    static func installSignalHandlers() {
        signalSources.withLock { sources in
            for number in handledSignals {
                signal(number, catchSignal)
            }
            guard sources.isEmpty else { return }
            for number in handledSignals {
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
                source.setEventHandler(handler: handleSignal)
                source.resume()
                sources.append(source)
            }
        }
    }
}
