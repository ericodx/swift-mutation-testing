struct BooleanLiteralReplacement: MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = BooleanLiteralVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
