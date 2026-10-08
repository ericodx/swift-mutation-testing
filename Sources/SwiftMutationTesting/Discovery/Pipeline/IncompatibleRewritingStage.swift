struct IncompatibleRewritingStage: Sendable {
    func run(indexed: [IndexedMutationPoint], sources: [ParsedSource]) -> [MutantDescriptor] {
        let incompatible = indexed.filter { !$0.isSchematizable }
        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.file.path, $0) })
        let rewriter = MutationRewriter()
        var hashByPath: [String: String] = [:]

        return incompatible.compactMap { entry in
            guard let source = sourceByPath[entry.mutation.filePath] else { return nil }
            let mutatedContent = rewriter.rewrite(
                source: source.file.content, applying: entry.mutation
            )
            let hash = hashByPath[source.file.path] ?? MutantCacheKey.hash(of: source.file.content)
            hashByPath[source.file.path] = hash
            return entry.toDescriptor(mutatedContent: mutatedContent, sourceContentHash: hash)
        }
    }
}
