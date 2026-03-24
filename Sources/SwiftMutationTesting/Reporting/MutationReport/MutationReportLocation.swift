struct MutationReportLocation: Sendable, Encodable {
    let start: MutationReportPosition
    let end: MutationReportPosition
}
