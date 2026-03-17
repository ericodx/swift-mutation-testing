struct RunnerSummary: Sendable {
    let results: [ExecutionResult]
    let totalDuration: Double

    var killed: [ExecutionResult] {
        results.filter {
            guard case .killed = $0.status else { return false }
            return true
        }
    }

    var crashes: [ExecutionResult] {
        results.filter { $0.status == .killedByCrash }
    }

    var survived: [ExecutionResult] {
        results.filter { $0.status == .survived }
    }

    var unviable: [ExecutionResult] {
        results.filter { $0.status == .unviable }
    }

    var timeouts: [ExecutionResult] {
        results.filter { $0.status == .timeout }
    }

    var noCoverage: [ExecutionResult] {
        results.filter { $0.status == .noCoverage }
    }

    var score: Double {
        let numerator = killed.count + crashes.count
        let denominator = killed.count + crashes.count + survived.count + timeouts.count + noCoverage.count

        guard denominator > 0 else { return 100.0 }

        return Double(numerator) / Double(denominator) * 100.0
    }

    var resultsByFile: [String: [ExecutionResult]] {
        Dictionary(grouping: results, by: { $0.descriptor.filePath })
    }
}
