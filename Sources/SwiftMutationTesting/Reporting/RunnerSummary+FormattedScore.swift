import Foundation

extension RunnerSummary {
    var formattedScore: String {
        score.map { String(format: "%.1f%%", $0) } ?? "n/a"
    }
}
