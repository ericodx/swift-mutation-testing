struct SonarPayload: Sendable, Encodable {
    let issues: [SonarIssue]
}
