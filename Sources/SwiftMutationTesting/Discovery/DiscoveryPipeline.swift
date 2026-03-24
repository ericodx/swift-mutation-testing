struct DiscoveryPipeline: Sendable {
    private static let registry: [(name: String, operator: any MutationOperator)] = [
        (name: "RelationalOperatorReplacement", operator: RelationalOperatorReplacement()),
        (name: "BooleanLiteralReplacement", operator: BooleanLiteralReplacement()),
        (name: "LogicalOperatorReplacement", operator: LogicalOperatorReplacement()),
        (name: "ArithmeticOperatorReplacement", operator: ArithmeticOperatorReplacement()),
        (name: "NegateConditional", operator: NegateConditional()),
        (name: "SwapTernary", operator: SwapTernary()),
        (name: "RemoveSideEffects", operator: RemoveSideEffects()),
    ]

    static let allOperatorNames: [String] = registry.map(\.name)

    func run(input: DiscoveryInput) async throws -> RunnerInput {
        let sourceFiles = try FileDiscoveryStage().run(input: input)
        let parsedSources = await ParsingStage().run(sourceFiles: sourceFiles)
        let ops = resolvedOperators(from: input.operators)
        let mutationPoints = await MutantDiscoveryStage(operators: ops).run(sources: parsedSources)
        let result = SchematizationStage().run(mutationPoints: mutationPoints, sources: parsedSources)

        return RunnerInput(
            projectPath: input.projectPath,
            scheme: input.scheme,
            destination: input.destination,
            timeout: input.timeout,
            concurrency: input.concurrency,
            noCache: input.noCache,
            schematizedFiles: result.schematizedFiles,
            supportFileContent: result.supportFileContent,
            mutants: result.descriptors
        )
    }

    private func resolvedOperators(from identifiers: [String]) -> [any MutationOperator] {
        if identifiers.isEmpty {
            return Self.registry.map(\.operator)
        }

        return Self.registry.compactMap { identifiers.contains($0.name) ? $0.operator : nil }
    }
}
