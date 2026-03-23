struct SonarIssue: Encodable {
    let engineId: String
    let ruleId: String
    let severity: String
    let type: String
    let primaryLocation: SonarLocation
}
