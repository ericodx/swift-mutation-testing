import SwiftSyntax

struct SuppressionFilter: Sendable {
    func filter(
        _ mutationPoints: [MutationPoint],
        suppressedRanges: [Range<AbsolutePosition>]
    ) -> [MutationPoint] {
        guard !suppressedRanges.isEmpty else {
            return mutationPoints
        }

        return mutationPoints.filter { point in
            let position = AbsolutePosition(utf8Offset: point.utf8Offset)
            return !suppressedRanges.contains { $0.contains(position) }
        }
    }
}
