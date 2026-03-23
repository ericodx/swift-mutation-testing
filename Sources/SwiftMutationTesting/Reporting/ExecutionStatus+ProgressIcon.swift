extension ExecutionStatus {
    var progressIcon: String {
        switch self {
        case .killed, .killedByCrash:
            return "✓"

        case .survived:
            return "✗"

        case .unviable:
            return "⚠"

        case .timeout:
            return "⏱"

        case .noCoverage:
            return "–"
        }
    }
}
