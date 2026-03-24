struct ArithmeticOperatorReplacement: Sendable, MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = ArithmeticOperatorVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
