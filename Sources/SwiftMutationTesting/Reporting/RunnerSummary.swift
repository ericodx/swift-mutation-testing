struct RunnerSummary: Sendable {
    let results: [ExecutionResult]
    let totalDuration: Double

    let killed: [ExecutionResult]
    let survived: [ExecutionResult]
    let unviable: [ExecutionResult]
    let timeouts: [ExecutionResult]
    let noCoverage: [ExecutionResult]
    let score: Double
    let resultsByFile: [String: [ExecutionResult]]
    let fromCache: [ExecutionResult]
    let integrityWarnings: [ExecutionResult]
    let activationNotMeasured: [ExecutionResult]

    init(results: [ExecutionResult], totalDuration: Double) {
        self.results = results
        self.totalDuration = totalDuration

        var killed: [ExecutionResult] = []
        var survived: [ExecutionResult] = []
        var unviable: [ExecutionResult] = []
        var timeouts: [ExecutionResult] = []
        var noCoverage: [ExecutionResult] = []
        var resultsByFile: [String: [ExecutionResult]] = [:]
        var fromCache: [ExecutionResult] = []
        var integrityWarnings: [ExecutionResult] = []
        var activationNotMeasured: [ExecutionResult] = []

        for result in results {
            switch result.status {
            case .killed, .killedByCrash: killed.append(result)
            case .survived: survived.append(result)
            case .unviable: unviable.append(result)
            case .timeout: timeouts.append(result)
            case .noCoverage: noCoverage.append(result)
            }
            resultsByFile[result.descriptor.filePath, default: []].append(result)
            if result.fromCache { fromCache.append(result) }
            if result.activated == false, result.status.isKill || result.status == .timeout {
                integrityWarnings.append(result)
            }
            if result.activated == nil, result.status != .unviable { activationNotMeasured.append(result) }
        }

        let detectedCount = killed.count + timeouts.count
        let validCount = detectedCount + survived.count + noCoverage.count
        self.score = validCount > 0 ? Double(detectedCount) / Double(validCount) * 100.0 : 100.0
        self.resultsByFile = resultsByFile
        self.fromCache = fromCache
        self.integrityWarnings = integrityWarnings
        self.activationNotMeasured = activationNotMeasured

        self.killed = killed
        self.survived = survived
        self.unviable = unviable
        self.timeouts = timeouts
        self.noCoverage = noCoverage
    }

    var detected: [ExecutionResult] {
        killed + timeouts
    }

    var undetected: [ExecutionResult] {
        survived + noCoverage
    }

    var files: [(path: String, summary: RunnerSummary)] {
        resultsByFile.sorted { $0.key < $1.key }.map { ($0.key, RunnerSummary(results: $0.value, totalDuration: 0)) }
    }

    static func byLocation(_ results: [ExecutionResult]) -> [ExecutionResult] {
        results.sorted {
            ($0.descriptor.filePath, $0.descriptor.line, $0.descriptor.column)
                < ($1.descriptor.filePath, $1.descriptor.line, $1.descriptor.column)
        }
    }
}
