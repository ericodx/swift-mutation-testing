@testable import SwiftMutationTesting

func mutationsWithIndices(
    _ source: ParsedSource,
    op: any MutationOperator = BooleanLiteralReplacement(),
    startIndex: Int = 0
) -> [(index: Int, point: MutationPoint)] {
    op.mutations(in: source).enumerated().map { (index: startIndex + $0.offset, point: $0.element) }
}
