struct RelationalOperatorReplacement: MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = RelationalOperatorVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}
