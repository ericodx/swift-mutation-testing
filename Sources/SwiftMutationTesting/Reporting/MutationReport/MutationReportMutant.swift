struct MutationReportMutant: Sendable, Encodable {
    let id: String
    let mutatorName: String
    let originalText: String
    let replacement: String
    let location: MutationReportLocation
    let status: String
    let description: String
    let killedBy: String?
}
