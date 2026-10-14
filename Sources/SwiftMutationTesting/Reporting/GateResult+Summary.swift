import Foundation

extension GateResult {
    var checksNewUndetected: Bool {
        checks.contains {
            if case .newUndetected = $0 { return true }
            return false
        }
    }

    var newUndetectedSummary: String {
        Self.count(newUndetected.count, "new undetected mutant")
    }

    var notes: [String] {
        var notes: [String] = []
        if !checksNewUndetected, !newUndetected.isEmpty {
            notes.append("\(newUndetectedSummary) since the baseline")
        }
        if let fixed = fixedCount, fixed > 0 {
            notes.append("\(Self.count(fixed, "mutant")) detected now that were undetected in the baseline")
        }
        return notes
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

extension GateResult.Check {
    var summary: String {
        switch self {
        case .minScore(let score, let minimum):
            guard let score else { return "no score, since no mutant could be tested (min \(Self.percent(minimum)))" }
            return "score \(Self.percent(score)) \(passed ? "≥" : "<") \(Self.percent(minimum))"

        case .scoreDrop(let drop, let maximum):
            guard let drop else { return "no score to compare with the baseline's (max drop \(Self.points(maximum)))" }
            guard drop > 0 else { return "score did not drop (max drop \(Self.points(maximum)))" }
            return "score drop \(Self.points(drop)) \(passed ? "≤" : ">") \(Self.points(maximum))"

        case .newUndetected(let found, let maximum):
            return "\(GateResult.count(found, "new undetected mutant")) (max \(maximum))"

        case .integrityWarnings(let found, let maximum):
            return "\(GateResult.count(found, "integrity warning")) (max \(maximum))"
        }
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func points(_ value: Double) -> String {
        String(format: "%.1f pts", value)
    }
}
