struct MutationReportMutant: Sendable, Encodable {
    let id: String
    let mutatorName: String
    let replacement: String
    let location: MutationReportLocation
    let status: String
    let description: String
}
