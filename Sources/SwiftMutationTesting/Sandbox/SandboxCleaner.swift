import Foundation

nonisolated(unsafe) private var activeSandboxPath: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) var sandboxCleanerExitHandler: @convention(c) (Int32) -> Void = { code in _exit(code) }

private func handleSignal(_: Int32) {
    SandboxCleaner.cleanupActiveSandbox()
    sandboxCleanerExitHandler(1)
}

enum SandboxCleaner {

    private static let prefix = "xmr-"

    static func cleanupActiveSandbox() {
        if let path = activeSandboxPath {
            let url = URL(fileURLWithPath: String(cString: path))
            try? FileManager.default.removeItem(at: url)
            path.deallocate()
            activeSandboxPath = nil
        }
    }

    static func removeOrphaned(in directory: URL = FileManager.default.temporaryDirectory) {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return }

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func register(_ sandbox: Sandbox) {
        let path = sandbox.rootURL.path
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: path.utf8.count + 1)
        _ = path.withCString { strcpy(buffer, $0) }
        activeSandboxPath = buffer
    }

    static func deregister() {
        if let path = activeSandboxPath {
            path.deallocate()
            activeSandboxPath = nil
        }
    }

    static func installSignalHandlers() {
        signal(SIGINT, handleSignal)
        signal(SIGTERM, handleSignal)
    }
}
