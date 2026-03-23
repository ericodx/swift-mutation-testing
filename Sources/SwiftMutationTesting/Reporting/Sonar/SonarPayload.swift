struct SonarPayload: Encodable {
    let issues: [SonarIssue]
}
