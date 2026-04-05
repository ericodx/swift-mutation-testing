struct IncompatibleRewritingStage: Sendable {
    func run(indexed: [IndexedMutationPoint], sources: [ParsedSource]) -> [MutantDescriptor] {
        let incompatible = indexed.filter { !$0.isSchematizable }
        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.file.path, $0) })
        let rewriter = MutationRewriter()

        return incompatible.compactMap { entry in
            guard let source = sourceByPath[entry.mutation.filePath] else { return nil }
            let mutatedContent = rewriter.rewrite(
                source: source.file.content, applying: entry.mutation
            )
            return entry.toDescriptor(mutatedContent: mutatedContent)
        }
    }
}
