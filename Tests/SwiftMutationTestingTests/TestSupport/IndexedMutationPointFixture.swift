@testable import SwiftMutationTesting

func makeIndexedMutationPoints(
    source: ParsedSource,
    operators: [any MutationOperator]
) -> [IndexedMutationPoint] {
    let points = operators.flatMap { $0.mutations(in: source) }
    return MutantIndexingStage().run(mutationPoints: points, sources: [source])
}
