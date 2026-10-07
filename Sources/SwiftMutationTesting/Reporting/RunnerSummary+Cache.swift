extension RunnerSummary {
    var cacheLine: String? {
        guard !fromCache.isEmpty else { return nil }
        return "Verdicts from cache: \(fromCache.count) of \(results.count)"
    }
}
