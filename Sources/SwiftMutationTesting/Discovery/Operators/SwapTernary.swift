struct SwapTernary: Sendable, MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = SwapTernaryVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
