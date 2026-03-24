extension ExecutionStatus {
    var mutationReportStatus: String {
        switch self {
        case .killed:
            return "Killed"

        case .killedByCrash:
            return "Crash"

        case .survived:
            return "Survived"

        case .unviable:
            return "Unviable"

        case .timeout:
            return "Timeout"

        case .noCoverage:
            return "NoCoverage"
        }
    }
}
