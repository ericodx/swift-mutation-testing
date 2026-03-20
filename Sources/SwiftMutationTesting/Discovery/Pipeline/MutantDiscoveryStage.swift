struct MutantDiscoveryStage {
    let operators: [any MutationOperator]

    func run(sources: [ParsedSource]) async -> [MutationPoint] {
        let extractor = SuppressionAnnotationExtractor()
        let filter = SuppressionFilter()

        let allMutations = await withTaskGroup(of: [MutationPoint].self) { group in
            for source in sources {
                group.addTask {
                    let suppressedRanges = extractor.extractSuppressedRanges(from: source.syntax)
                    let mutations = operators.flatMap { $0.mutations(in: source) }
                    return filter.filter(mutations, suppressedRanges: suppressedRanges)
                }
            }

            var collected: [MutationPoint] = []

            for await mutations in group {
                collected.append(contentsOf: mutations)
            }

            return collected
        }

        return allMutations.sorted {
            if $0.filePath != $1.filePath {
                return $0.filePath < $1.filePath
            }

            return $0.utf8Offset < $1.utf8Offset
        }
    }
}
