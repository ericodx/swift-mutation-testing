import Foundation

enum SandboxName {

    static let prefix = "xmr-"

    static var directory: URL {
        directory(environment: ProcessInfo.processInfo.environment)
    }

    static func directory(environment: [String: String]) -> URL {
        let temp =
            environment["TMPDIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return temp.appendingPathComponent("swift-mutation-testing")
    }

    static func make(pid: pid_t = getpid()) -> String {
        "\(prefix)\(pid)-\(UUID().uuidString)"
    }

    static func ownerPID(of name: String) -> pid_t? {
        guard name.hasPrefix(prefix) else { return nil }

        let fields = name.dropFirst(prefix.count)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        guard
            fields.count == 2,
            let pid = pid_t(fields[0]), pid > 0,
            UUID(uuidString: String(fields[1])) != nil
        else { return nil }

        return pid
    }

    static func isOwnerAlive(of name: String) -> Bool {
        guard let pid = ownerPID(of: name) else { return false }
        return ProcessTree.isAlive(pid)
    }
}
