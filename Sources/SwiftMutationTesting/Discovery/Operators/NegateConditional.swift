struct NegateConditional: Sendable, MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = NegateConditionalVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
