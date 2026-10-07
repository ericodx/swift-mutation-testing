import Foundation

enum CloneName {

    static let prefix = "XMR-"

    static func make(session: String, index: Int, pid: pid_t = getpid()) -> String {
        "\(prefix)\(pid)-\(session)-\(index)"
    }

    static func isOrphaned(_ name: String, isAlive: (pid_t) -> Bool = ProcessTree.isAlive) -> Bool {
        guard name.hasPrefix(prefix) else { return false }

        let fields = name.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)

        switch fields.count {
        case 2:
            return isSession(fields[0]) && Int(fields[1]) != nil
        case 3:
            guard let pid = pid_t(fields[0]), pid > 0, isSession(fields[1]), Int(fields[2]) != nil else { return false }
            return !isAlive(pid)
        default:
            return false
        }
    }

    // MARK: - Private

    private static func isSession(_ field: Substring) -> Bool {
        field.count == 8 && field.allSatisfy(\.isHexDigit)
    }
}
