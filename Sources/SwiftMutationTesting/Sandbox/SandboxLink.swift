import Foundation

enum SandboxLink {
    static func restore(at sandboxPath: String, to originalPath: String) throws {
        let fileManager = FileManager.default
        if (try? fileManager.attributesOfItem(atPath: sandboxPath)) != nil {
            try? fileManager.removeItem(atPath: sandboxPath)
        }
        do {
            try fileManager.createSymbolicLink(atPath: sandboxPath, withDestinationPath: originalPath)
        } catch {
            throw IntegrityError.sourceNotRestored(path: originalPath)
        }
    }
}
