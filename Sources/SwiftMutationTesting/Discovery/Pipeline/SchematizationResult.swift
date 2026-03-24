struct SchematizationResult: Sendable {
    let schematizedFiles: [SchematizedFile]
    let descriptors: [MutantDescriptor]
    let supportFileContent: String
}
