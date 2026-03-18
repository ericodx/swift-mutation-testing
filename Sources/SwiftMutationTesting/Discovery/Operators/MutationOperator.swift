protocol MutationOperator: Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
