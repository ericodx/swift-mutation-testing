extension ExecutionResult {
    static let unconfirmedKillSuffix = " failed only while other workers ran"

    static func unconfirmedKiller(in statusReason: String?) -> String? {
        guard let statusReason, statusReason.hasSuffix(unconfirmedKillSuffix) else { return nil }
        return String(statusReason.dropLast(unconfirmedKillSuffix.count))
    }

    var reportStatusReason: String? {
        if let unconfirmedKiller, !status.isKill, status != .timeout {
            return unconfirmedKiller + Self.unconfirmedKillSuffix
        }

        return switch (status, activated) {
        case (.killedByCrash, false): "crash without activation"
        case (.killedByCrash, _): "crash"
        case (.killed, false): "killed without activation"
        case (.timeout, false): "timed out without activation"
        default: nil
        }
    }
}
