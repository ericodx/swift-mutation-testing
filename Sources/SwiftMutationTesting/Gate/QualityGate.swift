struct QualityGate: Sendable {
    func evaluate(_ summary: RunnerSummary, policy: GatePolicy, baseline: Baseline?) -> GateResult {
        let baselineFingerprints = baseline.map { Set($0.undetected.map(\.fingerprint)) }
        let currentFingerprints = Set(summary.undetected.map(\.descriptor.fingerprint))

        let newUndetected =
            baselineFingerprints.map { known in
                summary.undetected.filter { !known.contains($0.descriptor.fingerprint) }
            } ?? []

        var checks: [GateResult.Check] = []

        if let minimum = policy.minScore {
            checks.append(.minScore(score: summary.score, minimum: minimum))
        }

        if let maximum = policy.maxScoreDrop, let baseline {
            let drop = summary.score.map { current in (baseline.score ?? current) - current }
            checks.append(.scoreDrop(drop: drop, maximum: maximum))
        }

        if let maximum = policy.maxNewSurvivors, baseline != nil {
            checks.append(.newUndetected(count: newUndetected.count, maximum: maximum))
        }

        if let maximum = policy.maxIntegrityWarnings {
            checks.append(.integrityWarnings(count: summary.integrityWarnings.count, maximum: maximum))
        }

        return GateResult(
            checks: checks,
            newUndetected: newUndetected.sorted {
                ($0.descriptor.filePath, $0.descriptor.line) < ($1.descriptor.filePath, $1.descriptor.line)
            },
            fixedCount: baselineFingerprints.map { $0.subtracting(currentFingerprints).count }
        )
    }
}
