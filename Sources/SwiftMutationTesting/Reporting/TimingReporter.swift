import Foundation

struct TimingReporter: Sendable {
    struct Line: Equatable, Sendable {
        let label: String
        let duration: Double
        let count: Int
    }

    struct Document: Codable, Equatable, Sendable {
        let totalDuration: Double
        let phases: [PhaseTiming]
    }

    static let otherLabel = "Other"

    func report(_ summary: RunnerSummary) {
        guard let text = format(summary) else { return }
        StandardOutput.write(text)
    }

    func format(_ summary: RunnerSummary) -> String? {
        let lines = lines(for: summary)
        guard !lines.isEmpty else { return nil }

        let width = lines.map(\.label.count).max() ?? 0
        var output = ["", "Time by phase:"]
        for line in lines {
            let label = line.label.padding(toLength: width, withPad: " ", startingAt: 0)
            let duration = String(format: "%8.1fs", line.duration)
            let count = line.count > 1 ? "   \(line.count)×" : ""
            output.append("  \(label)  \(duration)\(count)")
        }
        return output.joined(separator: "\n")
    }

    func lines(for summary: RunnerSummary) -> [Line] {
        guard !summary.phases.isEmpty else { return [] }

        var lines: [Line] = []
        var accounted = 0.0
        for phase in RunPhase.allCases {
            let entries = summary.phases.filter { $0.phase == phase }
            guard !entries.isEmpty else { continue }
            let duration = entries.reduce(0) { $0 + $1.duration }
            lines.append(Line(label: phase.label, duration: duration, count: entries.count))
            if phase != .discovery { accounted += duration }
        }
        lines.append(Line(label: Self.otherLabel, duration: max(0, summary.totalDuration - accounted), count: 1))
        return lines
    }

    func json(_ summary: RunnerSummary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(totalDuration: summary.totalDuration, phases: summary.phases))
    }
}
