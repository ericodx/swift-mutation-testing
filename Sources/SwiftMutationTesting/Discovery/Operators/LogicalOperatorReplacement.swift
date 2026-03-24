struct LogicalOperatorReplacement: Sendable, MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = LogicalOperatorVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
