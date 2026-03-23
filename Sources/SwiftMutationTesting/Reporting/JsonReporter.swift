import Foundation

struct JsonReporter {
    let outputPath: String
    let projectRoot: String

    func report(_ summary: RunnerSummary) throws {
        let payload = buildPayload(summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: URL(fileURLWithPath: outputPath))
    }

    private func buildPayload(_ summary: RunnerSummary) -> StrykerPayload {
        var fileEntries: [String: StrykerFile] = [:]

        for (filePath, results) in summary.resultsByFile {
            let relativePath = String(filePath.dropFirst(projectRoot.count))
            let source = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let mutants = results.map { strykerMutant(from: $0) }
            fileEntries[relativePath] = StrykerFile(language: "swift", source: source, mutants: mutants)
        }

        return StrykerPayload(
            schemaVersion: "1",
            thresholds: StrykerThresholds(high: 80, low: 60),
            projectRoot: projectRoot,
            files: fileEntries
        )
    }

    private func strykerMutant(from result: ExecutionResult) -> StrykerMutant {
        let descriptor = result.descriptor
        return StrykerMutant(
            id: descriptor.id,
            mutatorName: descriptor.operatorIdentifier,
            replacement: descriptor.mutatedText,
            location: StrykerLocation(
                start: StrykerPosition(line: descriptor.line, column: descriptor.column),
                end: StrykerPosition(line: descriptor.line, column: descriptor.column + descriptor.originalText.count)
            ),
            status: result.status.strykerStatus,
            description: descriptor.description
        )
    }
}

extension ExecutionStatus {
    fileprivate var strykerStatus: String {
        switch self {
        case .killed:
            return "Killed"

        case .killedByCrash:
            return "Crash"

        case .survived:
            return "Survived"

        case .unviable:
            return "Unviable"

        case .timeout:
            return "Timeout"

        case .noCoverage:
            return "NoCoverage"
        }
    }
}

private struct StrykerPayload: Encodable {
    let schemaVersion: String
    let thresholds: StrykerThresholds
    let projectRoot: String
    let files: [String: StrykerFile]
}

private struct StrykerThresholds: Encodable {
    let high: Int
    let low: Int
}

private struct StrykerFile: Encodable {
    let language: String
    let source: String
    let mutants: [StrykerMutant]
}

private struct StrykerMutant: Encodable {
    let id: String
    let mutatorName: String
    let replacement: String
    let location: StrykerLocation
    let status: String
    let description: String
}

private struct StrykerLocation: Encodable {
    let start: StrykerPosition
    let end: StrykerPosition
}

private struct StrykerPosition: Encodable {
    let line: Int
    let column: Int
}
