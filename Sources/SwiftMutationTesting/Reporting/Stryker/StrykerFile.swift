struct StrykerFile: Encodable {
    let language: String
    let source: String
    let mutants: [StrykerMutant]
}
