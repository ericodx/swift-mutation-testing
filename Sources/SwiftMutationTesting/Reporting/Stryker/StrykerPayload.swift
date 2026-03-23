struct StrykerPayload: Encodable {
    let schemaVersion: String
    let thresholds: StrykerThresholds
    let projectRoot: String
    let files: [String: StrykerFile]
}
