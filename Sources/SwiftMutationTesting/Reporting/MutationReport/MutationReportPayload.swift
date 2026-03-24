struct MutationReportPayload: Sendable, Encodable {
    let schemaVersion: String
    let thresholds: MutationReportThresholds
    let projectRoot: String
    let files: [String: MutationReportFile]
}
