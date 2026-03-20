import Foundation

struct TextReporter {
    init(projectRoot: String = "") {
        resolvedRoot =
            projectRoot.isEmpty
            ? ""
            : URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
    }

    private let resolvedRoot: String

    func report(_ summary: RunnerSummary) {
        print(format(summary))
    }

    func format(_ summary: RunnerSummary) -> String {
        var lines: [String] = []

        lines.append("")
        lines.append("Results by file:")
        for (filePath, fileResults) in summary.resultsByFile.sorted(by: { $0.key < $1.key }) {
            let file = RunnerSummary(results: fileResults, totalDuration: 0)
            let score = String(format: "%.1f", file.score)
            let stats = [
                "killed: \(file.killed.count)",
                "crashes: \(file.crashes.count)",
                "survived: \(file.survived.count)",
                "unviable: \(file.unviable.count)",
                "timeout: \(file.timeouts.count)",
            ].joined(separator: "   ")
            lines.append("  \(relative(filePath))    score: \(score)%   \(stats)")
        }

        let unkilledMutants = summary.survived + summary.noCoverage
        if !unkilledMutants.isEmpty {
            lines.append("")
            lines.append("Survived mutants:")
            let sorted = unkilledMutants.sorted {
                ($0.descriptor.filePath, $0.descriptor.line) < ($1.descriptor.filePath, $1.descriptor.line)
            }
            for result in sorted {
                let desc = result.descriptor
                lines.append(
                    "  \(relative(desc.filePath)):\(desc.line):\(desc.column)"
                        + "   \(desc.operatorIdentifier)"
                )
            }
        }

        lines.append("")
        lines.append("Overall mutation score: \(String(format: "%.1f", summary.score))%")
        lines.append(
            "Killed: \(summary.killed.count)"
                + " / Crashes: \(summary.crashes.count)"
                + " / Survived: \(summary.survived.count)"
                + " / Unviable: \(summary.unviable.count)"
                + " / Timeouts: \(summary.timeouts.count)"
                + " / NoCoverage: \(summary.noCoverage.count)"
        )
        lines.append("Total duration: \(String(format: "%.1f", summary.totalDuration))s")

        return lines.joined(separator: "\n")
    }

    private func relative(_ path: String) -> String {
        guard !resolvedRoot.isEmpty else { return path }
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix(resolvedRoot) else { return path }
        return String(resolvedPath.dropFirst(resolvedRoot.count).drop(while: { $0 == "/" }))
    }
}
