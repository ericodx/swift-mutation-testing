import Foundation

extension RunnerSummary {
    var formattedScore: String {
        String(format: "%.1f%%", score)
    }
}
