struct RunnerSummary: Sendable {
    let results: [ExecutionResult]
    let totalDuration: Double

    var killed: [ExecutionResult] {
        results.filter {
            switch $0.status {
            case .killed, .killedByCrash: return true
            default: return false
            }
        }
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
        let numerator = killed.count
        let denominator = killed.count + survived.count + timeouts.count + noCoverage.count

        guard denominator > 0 else { return 100.0 }

        return Double(numerator) / Double(denominator) * 100.0
    }

    var resultsByFile: [String: [ExecutionResult]] {
        Dictionary(grouping: results, by: { $0.descriptor.filePath })
    }
}
