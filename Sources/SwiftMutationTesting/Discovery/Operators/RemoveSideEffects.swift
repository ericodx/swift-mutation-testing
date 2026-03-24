struct RemoveSideEffects: Sendable, MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = RemoveSideEffectsVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
