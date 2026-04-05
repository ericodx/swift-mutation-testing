struct SchematizationStage: Sendable {
    static let supportFileContent = """
        import Foundation

        var __swiftMutationTestingID: String {
            ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
        }
        """

    func run(indexed: [IndexedMutationPoint], sources: [ParsedSource]) -> ([SchematizedFile], [MutantDescriptor]) {
        let schematizable = indexed.filter { $0.isSchematizable }
        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.file.path, $0) })
        let byFile = Dictionary(grouping: schematizable) { $0.mutation.filePath }
        let generator = SchemataGenerator()
        var schematizedFiles: [SchematizedFile] = []
        var descriptors: [MutantDescriptor] = []

        for (filePath, entries) in byFile {
            guard let source = sourceByPath[filePath] else { continue }

            let mutations = entries.map { (index: $0.index, point: $0.mutation) }
            let content = generator.generate(source: source, mutations: mutations)
            schematizedFiles.append(SchematizedFile(originalPath: filePath, schematizedContent: content))

            for entry in entries {
                descriptors.append(entry.toDescriptor(mutatedContent: nil))
            }
        }

        return (schematizedFiles, descriptors)
    }
}
