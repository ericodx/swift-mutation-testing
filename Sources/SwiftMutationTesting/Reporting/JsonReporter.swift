import Foundation

struct JsonReporter: Sendable {
    let outputPath: String
    let projectRoot: String

    func report(_ summary: RunnerSummary) throws {
        let payload = buildPayload(summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: URL(fileURLWithPath: outputPath))
    }

    private func buildPayload(_ summary: RunnerSummary) -> MutationReportPayload {
        var fileEntries: [String: MutationReportFile] = [:]

        for (filePath, results) in summary.resultsByFile {
            let relativePath = String(filePath.dropFirst(projectRoot.count))
            let source = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let mutants = results.map { mutationReportMutant(from: $0) }
            fileEntries[relativePath] = MutationReportFile(language: "swift", source: source, mutants: mutants)
        }

        return MutationReportPayload(
            schemaVersion: "1",
            thresholds: MutationReportThresholds(high: 80, low: 60),
            projectRoot: projectRoot,
            files: fileEntries
        )
    }

    private func mutationReportMutant(from result: ExecutionResult) -> MutationReportMutant {
        let descriptor = result.descriptor
        return MutationReportMutant(
            id: descriptor.id,
            mutatorName: descriptor.operatorIdentifier,
            replacement: descriptor.mutatedText,
            location: MutationReportLocation(
                start: MutationReportPosition(line: descriptor.line, column: descriptor.column),
                end: MutationReportPosition(
                    line: descriptor.line, column: descriptor.column + descriptor.originalText.count)
            ),
            status: result.status.mutationReportStatus,
            description: descriptor.description
        )
    }
}
