struct GateResult: Sendable {
    let checks: [Check]
    let newUndetected: [ExecutionResult]
    let fixedCount: Int?

    var passed: Bool {
        checks.allSatisfy(\.passed)
    }

    enum Check: Sendable, Equatable {
        case minScore(score: Double?, minimum: Double)
        case scoreDrop(drop: Double?, maximum: Double)
        case newUndetected(count: Int, maximum: Int)
        case integrityWarnings(count: Int, maximum: Int)

        var passed: Bool {
            switch self {
            case .minScore(let score, let minimum): score.map { $0 >= minimum } ?? false
            case .scoreDrop(let drop, let maximum): drop.map { $0 <= maximum } ?? false
            case .newUndetected(let count, let maximum): count <= maximum
            case .integrityWarnings(let count, let maximum): count <= maximum
            }
        }
    }
}
