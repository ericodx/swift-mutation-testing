import Foundation

struct HtmlReporter: Sendable {
    let outputPath: String
    let projectRoot: String

    func report(_ summary: RunnerSummary) throws {
        let html = buildHtml(summary)
        try html.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
    }

    private func buildHtml(_ summary: RunnerSummary) -> String {
        let score = String(format: "%.1f", summary.score)
        let rows = buildRows(summary)
        let totals = buildTotals(summary)
        return htmlTemplate(score: score, totals: totals, rows: rows)
    }

    private func scoreColorClass(_ score: Double) -> String {
        if score == 100 { return "score-green" }
        if score >= 50 { return "score-yellow" }
        return "score-red"
    }

    private func buildRows(_ summary: RunnerSummary) -> String {
        var rows = ""
        for (filePath, results) in summary.resultsByFile.sorted(by: { $0.key < $1.key }) {
            let file = RunnerSummary(results: results, totalDuration: 0)
            let fileScore = String(format: "%.1f", file.score)
            let colorClass = scoreColorClass(file.score)
            let relativePath = String(filePath.dropFirst(projectRoot.count))
            let details = buildSurvivedDetails(file.survived)
            rows +=
                "<tr>"
                + "<td>\(relativePath)\(details)</td><td class=\"\(colorClass)\">\(fileScore)%</td>"
                + "<td>\(file.killed.count)</td><td>\(file.survived.count)</td>"
                + "<td>\(file.timeouts.count)</td><td>\(file.unviable.count)</td>"
                + "<td>\(file.noCoverage.count)</td>"
                + "</tr>\n"
        }
        return rows
    }

    private func buildSurvivedDetails(_ survived: [ExecutionResult]) -> String {
        guard !survived.isEmpty else { return "" }
        let mutantRows = survived.sorted { $0.descriptor.line < $1.descriptor.line }.map { result in
            let descriptor = result.descriptor
            return "<tr><td>\(descriptor.line)</td><td>\(descriptor.column)</td>"
                + "<td>\(descriptor.operatorIdentifier)</td><td>\(descriptor.description)</td></tr>"
        }.joined()
        return "<details><summary>Survived mutants (\(survived.count))</summary>"
            + "<table class=\"mutant-table\"><thead><tr>"
            + "<th>Line</th><th>Col</th><th>Operator</th><th>Mutation</th>"
            + "</tr></thead><tbody>\(mutantRows)</tbody></table></details>"
    }

    private func buildTotals(_ summary: RunnerSummary) -> String {
        let pairs: [(String, Int)] = [
            ("Killed", summary.killed.count),
            ("Survived", summary.survived.count),
            ("Timeouts", summary.timeouts.count),
            ("Unviable", summary.unviable.count),
            ("NoCoverage", summary.noCoverage.count),
        ]
        return pairs.map { "\($0.0): \($0.1)" }.joined(separator: " / ")
    }

    private func htmlTemplate(score: String, totals: String, rows: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Mutation Testing Report</title>
            <style>
                body { font-family: sans-serif; margin: 2rem; }
                h1 { font-size: 1.5rem; }
                .score { font-size: 2rem; font-weight: bold; }
                table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
                th, td { border: 1px solid #ccc; padding: 0.5rem 1rem; text-align: left; }
                th { background: #f4f4f4; }
                .score-green { background: #d4f1dc; }
                .score-yellow { background: #fef9c3; }
                .score-red { background: #fde8e8; }
                details { margin-top: 0.5rem; font-size: 0.85rem; }
                details summary { cursor: pointer; color: #555; }
                .mutant-table { margin-top: 0.25rem; width: 100%; font-size: 0.8rem; }
                .mutant-table th, .mutant-table td { border: 1px solid #e0e0e0; padding: 0.2rem 0.4rem; }
                .mutant-table th { background: #fafafa; }
            </style>
        </head>
        <body>
            <h1>Mutation Testing Report</h1>
            <p class="score">Score: \(score)%</p>
            <p>\(totals)</p>
            <table>
                <thead>
                    <tr>
                        <th>File</th><th>Score</th>
                        <th>Killed</th><th>Survived</th>
                        <th>Timeouts</th><th>Unviable</th>
                        <th>NoCoverage</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </body>
        </html>
        """
    }
}
