import CryptoKit
import Foundation

struct WarmSandboxes: Sendable {
    static let prefix = "warm-"
    static let lockName = "lock"
    static let keptDirectories: Set<String> = [".build", ".xmr-derived-data"]

    var directory: URL = SandboxName.directory

    struct Slot: Sendable {
        let index: Int
        let lockDescriptor: Int32

        func unlock() {
            close(lockDescriptor)
        }
    }

    struct LockError: Error, LocalizedError {
        let path: String

        var errorDescription: String? {
            "The warm sandbox lock at \(path) could not be created."
        }
    }

    static func key(for projectPath: String) -> String {
        let canonical = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().path
        return SHA256.hash(data: Data(canonical.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func name(for projectPath: String, slot: Int) -> String {
        "\(prefix)\(key(for: projectPath))-\(slot)"
    }

    func claim(projectPath: String) throws -> (URL, Slot) {
        var index = 0
        while true {
            let url = directory.appendingPathComponent(Self.name(for: projectPath, slot: index))
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if let descriptor = try Self.lock(url.appendingPathComponent(Self.lockName)) {
                return (url, Slot(index: index, lockDescriptor: descriptor))
            }
            index += 1
        }
    }

    func slots(of projectPath: String) -> [URL] {
        let prefix = "\(Self.prefix)\(Self.key(for: projectPath))-"
        let contents =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.path < $1.path }
    }

    func removeAll(projectPath: String) {
        for url in slots(of: projectPath) {
            guard let descriptor = try? Self.lock(url.appendingPathComponent(Self.lockName)) else { continue }
            try? FileManager.default.removeItem(at: url)
            close(descriptor)
        }
    }

    func prune(_ sandboxURL: URL, keeping kept: Set<String>) throws {
        try prune(sandboxURL, relativePath: "", keeping: kept)
    }

    // MARK: - Private

    private static func lock(_ url: URL) throws -> Int32? {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw LockError(path: url.path) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        _ = ftruncate(descriptor, 0)
        let owner = "\(getpid())\n"
        owner.withCString { _ = write(descriptor, $0, strlen($0)) }
        return descriptor
    }

    private func prune(_ directory: URL, relativePath: String, keeping kept: Set<String>) throws {
        let items = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )

        for item in items {
            let name = item.lastPathComponent
            let itemRelativePath = relativePath.isEmpty ? name : relativePath + "/" + name

            if relativePath.isEmpty, Self.keptDirectories.contains(name) || name == Self.lockName { continue }
            if kept.contains(itemRelativePath) { continue }

            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let holdsKeptFiles = kept.contains { $0.hasPrefix(itemRelativePath + "/") }

            if holdsKeptFiles, values.isDirectory == true, values.isSymbolicLink != true {
                try prune(item, relativePath: itemRelativePath, keeping: kept)
            } else {
                try FileManager.default.removeItem(at: item)
            }
        }
    }
}
