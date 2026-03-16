import Foundation

struct Sandbox: Sendable {
    let rootURL: URL

    func cleanup() throws {
        try FileManager.default.removeItem(at: rootURL)
    }
}
