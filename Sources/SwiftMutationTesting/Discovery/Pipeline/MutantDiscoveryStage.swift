struct MutantDiscoveryStage: Sendable {
    let operators: [any MutationOperator]

    func run(sources: [ParsedSource]) async -> [MutationPoint] {
        let extractor = SuppressionAnnotationExtractor()
        let filter = SuppressionFilter()
        let loopExtractor = InfiniteLoopBodyExtractor()
        let loopFilter = InfiniteLoopFilter()

        let allMutations = await withTaskGroup(of: [MutationPoint].self) { group in
            for source in sources {
                group.addTask {
                    self.mutationPoints(
                        for: source,
                        extractor: extractor,
                        filter: filter,
                        loopExtractor: loopExtractor,
                        loopFilter: loopFilter
                    )
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

    private func mutationPoints(
        for source: ParsedSource,
        extractor: SuppressionAnnotationExtractor,
        filter: SuppressionFilter,
        loopExtractor: InfiniteLoopBodyExtractor,
        loopFilter: InfiniteLoopFilter
    ) -> [MutationPoint] {
        let suppressedRanges = extractor.extractSuppressedRanges(from: source.syntax)
        let loopBodyRanges = loopExtractor.extractLoopBodyRanges(from: source.syntax)
        let mutations = operators.flatMap { $0.mutations(in: source) }
        let afterSuppression = filter.filter(mutations, suppressedRanges: suppressedRanges)
        return loopFilter.filter(afterSuppression, loopBodyRanges: loopBodyRanges)
    }
}
