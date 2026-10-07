struct MutantDiscoveryStage: Sendable {
    static let standardExclusions: [any MutationExclusion] = [
        SuppressionFilter(), InfiniteLoopFilter(), InactiveRegionFilter(),
    ]

    let operators: [any MutationOperator]
    let exclusions: [any MutationExclusion]

    init(operators: [any MutationOperator], exclusions: [any MutationExclusion] = Self.standardExclusions) {
        self.operators = operators
        self.exclusions = exclusions
    }

    func run(sources: [ParsedSource]) async -> [MutationPoint] {
        let allMutations = await withTaskGroup(of: [MutationPoint].self) { group in
            for source in sources {
                group.addTask {
                    self.mutationPoints(for: source)
                }
            }

            var collected: [MutationPoint] = []

            for await mutations in group {
                collected.append(contentsOf: mutations)
            }

            return collected
        }

        return allMutations.sorted(by: MutationPoint.inSourceOrder)
    }

    private func mutationPoints(for source: ParsedSource) -> [MutationPoint] {
        exclusions.reduce(operators.flatMap { $0.mutations(in: source) }) { points, exclusion in
            exclusion.filter(points, in: source)
        }
    }
}
