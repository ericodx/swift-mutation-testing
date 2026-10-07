import Foundation

struct Baseline: Sendable, Codable, Equatable {
    static let formatVersion = 1

    let formatVersion: Int
    let toolVersion: String
    let createdAt: Date
    let score: Double
    let scope: BaselineScope
    let undetected: [BaselineEntry]

    init(
        formatVersion: Int = Baseline.formatVersion,
        toolVersion: String,
        createdAt: Date,
        score: Double,
        scope: BaselineScope,
        undetected: [BaselineEntry]
    ) {
        self.formatVersion = formatVersion
        self.toolVersion = toolVersion
        self.createdAt = createdAt
        self.score = score
        self.scope = scope
        self.undetected = undetected.sorted {
            ($0.file, $0.line, $0.fingerprint) < ($1.file, $1.line, $1.fingerprint)
        }
    }

    init(summary: RunnerSummary, scope: BaselineScope, projectPath: String, toolVersion: String, createdAt: Date) {
        let paths = ProjectRelativePath.Resolver(projectPath: projectPath)
        self.init(
            toolVersion: toolVersion,
            createdAt: createdAt,
            score: summary.score,
            scope: scope,
            undetected: summary.undetected.map { result in
                let descriptor = result.descriptor
                return BaselineEntry(
                    fingerprint: descriptor.fingerprint,
                    file: paths.make(for: descriptor.filePath),
                    line: descriptor.line,
                    operatorIdentifier: descriptor.operatorIdentifier,
                    original: descriptor.originalText,
                    replacement: descriptor.mutatedText,
                    status: result.status == .noCoverage ? "noCoverage" : "survived"
                )
            }
        )
    }
}
