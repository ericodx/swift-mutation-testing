struct DiscoveryPipeline: Sendable {
    static let allOperatorNames: [String] = [
        "RelationalOperatorReplacement",
        "BooleanLiteralReplacement",
        "LogicalOperatorReplacement",
        "ArithmeticOperatorReplacement",
        "NegateConditional",
        "SwapTernary",
        "RemoveSideEffects",
    ]

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
        let all: [(String, any MutationOperator)] = [
            ("RelationalOperatorReplacement", RelationalOperatorReplacement()),
            ("BooleanLiteralReplacement", BooleanLiteralReplacement()),
            ("LogicalOperatorReplacement", LogicalOperatorReplacement()),
            ("ArithmeticOperatorReplacement", ArithmeticOperatorReplacement()),
            ("NegateConditional", NegateConditional()),
            ("SwapTernary", SwapTernary()),
            ("RemoveSideEffects", RemoveSideEffects()),
        ]

        if identifiers.isEmpty {
            return all.map { $0.1 }
        }

        return all.compactMap { id, op in identifiers.contains(id) ? op : nil }
    }
}
