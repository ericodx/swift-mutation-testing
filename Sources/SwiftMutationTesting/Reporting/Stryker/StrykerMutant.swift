struct StrykerMutant: Encodable {
    let id: String
    let mutatorName: String
    let replacement: String
    let location: StrykerLocation
    let status: String
    let description: String
}
