struct MutationReportFile: Sendable, Encodable {
    let language: String
    let source: String
    let mutants: [MutationReportMutant]
}
