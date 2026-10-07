import Foundation

struct JsonReporter: Sendable {
    let outputPath: String
    let projectRoot: String

    func report(_ summary: RunnerSummary, identity: RunIdentity? = nil) throws {
        let payload = buildPayload(summary, identity: identity)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: URL(fileURLWithPath: outputPath))
    }

    private func buildPayload(_ summary: RunnerSummary, identity: RunIdentity?) -> MutationReportPayload {
        var fileEntries: [String: MutationReportFile] = [:]

        for (filePath, results) in summary.resultsByFile {
            let relative = ProjectRelativePath.make(for: filePath, in: projectRoot)
            let relativePath = relative == filePath ? filePath : "/" + relative
            let source = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let mutants = results.map { mutationReportMutant(from: $0) }
            fileEntries[relativePath] = MutationReportFile(language: "swift", source: source, mutants: mutants)
        }

        return MutationReportPayload(
            schemaVersion: "1",
            thresholds: MutationReportThresholds(high: 80, low: 60),
            projectRoot: projectRoot,
            files: fileEntries,
            config: identity.map {
                MutationReportConfig(
                    toolVersion: Version.number, planSha256: $0.planSha256, shard: $0.shard?.description
                )
            }
        )
    }

    private func mutationReportMutant(from result: ExecutionResult) -> MutationReportMutant {
        let descriptor = result.descriptor
        return MutationReportMutant(
            id: descriptor.id,
            mutatorName: descriptor.operatorIdentifier,
            originalText: descriptor.originalText,
            replacement: descriptor.mutatedText,
            location: MutationReportLocation(
                start: MutationReportPosition(line: descriptor.line, column: descriptor.column),
                end: MutationReportPosition(
                    line: descriptor.line, column: descriptor.column + descriptor.originalText.utf8.count)
            ),
            status: result.status.mutationReportStatus,
            statusReason: result.reportStatusReason,
            description: descriptor.description,
            killedBy: killedBy(from: result.status),
            duration: milliseconds(of: result.testDuration),
            fingerprint: descriptor.fingerprint,
            activated: result.activated
        )
    }

    private func milliseconds(of seconds: Double) -> Int? {
        seconds > 0 ? Int((seconds * 1000).rounded()) : nil
    }

    private func killedBy(from status: ExecutionStatus) -> [String]? {
        if case .killed(let by) = status { return [by] }
        return nil
    }
}
