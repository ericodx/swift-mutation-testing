import SwiftSyntax

struct InfiniteLoopFilter: Sendable {

    private static let riskyOperators: Set<String> = [
        "ArithmeticOperatorReplacement",
        "RemoveSideEffects",
    ]

    func filter(
        _ mutationPoints: [MutationPoint],
        loopBodyRanges: [Range<AbsolutePosition>]
    ) -> [MutationPoint] {
        guard !loopBodyRanges.isEmpty else {
            return mutationPoints
        }

        return mutationPoints.filter { point in
            guard Self.riskyOperators.contains(point.operatorIdentifier) else {
                return true
            }

            let position = AbsolutePosition(utf8Offset: point.utf8Offset)
            return !loopBodyRanges.contains { $0.contains(position) }
        }
    }
}
