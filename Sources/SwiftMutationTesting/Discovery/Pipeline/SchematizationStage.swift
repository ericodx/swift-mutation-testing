import Foundation

struct SchematizationStage: Sendable {
    private static let supportFileContent = """
        import Foundation

        var __swiftMutationTestingID: String {
            ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
        }
        """

    func run(mutationPoints: [MutationPoint], sources: [ParsedSource]) -> SchematizationResult {
        let sorted = mutationPoints.sorted {
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            return $0.utf8Offset < $1.utf8Offset
        }

        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.file.path, $0) })
        let visitors = buildVisitors(for: sources)
        let indexed = assignIndices(sorted: sorted, visitors: visitors)
        let byFile = Dictionary(grouping: indexed) { $0.mutation.filePath }
        let generator = SchemataGenerator()
        let rewriter = MutationRewriter()
        var descriptors: [MutantDescriptor] = []
        var schematizedFiles: [SchematizedFile] = []

        for (filePath, entries) in byFile {
            guard let source = sourceByPath[filePath] else { continue }

            let schematizable = entries.filter { $0.isSchematizable }
            let incompatible = entries.filter { !$0.isSchematizable }

            if !schematizable.isEmpty {
                let mutations = schematizable.map { (index: $0.index, point: $0.mutation) }
                let content = generator.generate(source: source, mutations: mutations)
                schematizedFiles.append(SchematizedFile(originalPath: filePath, schematizedContent: content))

                for entry in schematizable {
                    descriptors.append(
                        descriptor(
                            from: entry.mutation, id: mutantID(entry.index),
                            isSchematizable: true, mutatedContent: nil
                        ))
                }
            }

            for entry in incompatible {
                let mutatedContent = rewriter.rewrite(source: source.file.content, applying: entry.mutation)
                descriptors.append(
                    descriptor(
                        from: entry.mutation, id: mutantID(entry.index),
                        isSchematizable: false, mutatedContent: mutatedContent
                    ))
            }
        }

        return SchematizationResult(
            schematizedFiles: schematizedFiles,
            descriptors: descriptors.sorted { indexFromID($0.id) < indexFromID($1.id) },
            supportFileContent: Self.supportFileContent
        )
    }

    private func buildVisitors(for sources: [ParsedSource]) -> [String: TypeScopeVisitor] {
        var result: [String: TypeScopeVisitor] = [:]

        for source in sources {
            let visitor = TypeScopeVisitor()
            visitor.walk(source.syntax)
            result[source.file.path] = visitor
        }

        return result
    }

    private func assignIndices(
        sorted: [MutationPoint],
        visitors: [String: TypeScopeVisitor]
    ) -> [(index: Int, mutation: MutationPoint, isSchematizable: Bool)] {
        sorted.enumerated().map { index, mutation in
            let schematizable = visitors[mutation.filePath]?.isSchematizable(utf8Offset: mutation.utf8Offset) ?? false
            return (index: index, mutation: mutation, isSchematizable: schematizable)
        }
    }

    private func mutantID(_ index: Int) -> String {
        "swift-mutation-testing_\(index)"
    }

    private func indexFromID(_ id: String) -> Int {
        Int(id.replacingOccurrences(of: "swift-mutation-testing_", with: "")) ?? 0
    }

    private func descriptor(
        from mutation: MutationPoint,
        id: String,
        isSchematizable: Bool,
        mutatedContent: String?
    ) -> MutantDescriptor {
        MutantDescriptor(
            id: id,
            filePath: mutation.filePath,
            line: mutation.line,
            column: mutation.column,
            utf8Offset: mutation.utf8Offset,
            originalText: mutation.originalText,
            mutatedText: mutation.mutatedText,
            operatorIdentifier: mutation.operatorIdentifier,
            replacementKind: mutation.replacement,
            description: mutation.description,
            isSchematizable: isSchematizable,
            mutatedSourceContent: mutatedContent
        )
    }
}
