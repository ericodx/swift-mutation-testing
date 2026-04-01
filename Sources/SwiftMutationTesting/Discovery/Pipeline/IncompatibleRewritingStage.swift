struct IncompatibleRewritingStage: Sendable {
    func run(indexed: [IndexedMutationPoint], sources: [ParsedSource]) -> [MutantDescriptor] {
        let incompatible = indexed.filter { !$0.isSchematizable }
        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.file.path, $0) })
        let rewriter = MutationRewriter()

        return incompatible.compactMap { entry in
            guard let source = sourceByPath[entry.mutation.filePath] else { return nil }
            let mutatedContent = rewriter.rewrite(source: source.file.content, applying: entry.mutation)
            return makeDescriptor(from: entry.mutation, id: mutantID(entry.index), isSchematizable: false, mutatedContent: mutatedContent)
        }
    }

    private func mutantID(_ index: Int) -> String {
        "swift-mutation-testing_\(index)"
    }

    private func makeDescriptor(
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
