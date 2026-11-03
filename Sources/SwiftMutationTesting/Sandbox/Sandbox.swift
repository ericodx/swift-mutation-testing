import Foundation

struct Sandbox: Sendable {
    let rootURL: URL
    var slot: WarmSandboxes.Slot?

    var isPersistent: Bool { slot != nil }

    func cleanup() throws {
        if let slot {
            slot.unlock()
        } else {
            try FileManager.default.removeItem(at: rootURL)
        }
    }
}
