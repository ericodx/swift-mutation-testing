enum SlowestFirst {
    static let loopingOperators: Set<String> = ["NegateConditional", "RelationalOperatorReplacement"]

    static func order(_ mutants: [MutantDescriptor], durations: [Double?]) -> [MutantDescriptor] {
        zip(mutants, durations).enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (rank(lhs.element), rank(rhs.element))
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element.0)
    }

    static func isLikelyToLoop(_ mutant: MutantDescriptor) -> Bool {
        mutant.isInLoopCondition && loopingOperators.contains(mutant.operatorIdentifier)
    }

    // MARK: - Private

    private static func rank(_ entry: (MutantDescriptor, Double?)) -> (Int, Double) {
        guard let duration = entry.1 else { return (isLikelyToLoop(entry.0) ? 0 : 1, 0) }
        return (2, -duration)
    }
}
