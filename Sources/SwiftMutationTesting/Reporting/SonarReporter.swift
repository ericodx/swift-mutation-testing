import Foundation

struct SonarReporter {
    let outputPath: String
    let projectRoot: String

    func report(_ summary: RunnerSummary) throws {
        let issues = buildIssues(summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(SonarPayload(issues: issues))
        try data.write(to: URL(fileURLWithPath: outputPath))
    }

    private func buildIssues(_ summary: RunnerSummary) -> [SonarIssue] {
        let reportable = summary.survived.map { ($0, "MAJOR") } + summary.noCoverage.map { ($0, "MINOR") }
        return reportable.map { result, severity in
            let descriptor = result.descriptor
            let relativePath = String(descriptor.filePath.dropFirst(projectRoot.count + 1))
            return SonarIssue(
                engineId: "swift-mutation-testing",
                ruleId: descriptor.operatorIdentifier,
                severity: severity,
                type: "CODE_SMELL",
                primaryLocation: SonarLocation(
                    message: descriptor.description,
                    filePath: relativePath,
                    textRange: SonarRange(
                        startLine: descriptor.line,
                        endLine: descriptor.line,
                        startColumn: descriptor.column,
                        endColumn: descriptor.column + descriptor.originalText.count
                    )
                )
            )
        }
    }
}

private struct SonarPayload: Encodable {
    let issues: [SonarIssue]
}

private struct SonarIssue: Encodable {
    let engineId: String
    let ruleId: String
    let severity: String
    let type: String
    let primaryLocation: SonarLocation
}

private struct SonarLocation: Encodable {
    let message: String
    let filePath: String
    let textRange: SonarRange
}

private struct SonarRange: Encodable {
    let startLine: Int
    let endLine: Int
    let startColumn: Int
    let endColumn: Int
}
