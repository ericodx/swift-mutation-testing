import SwiftSyntax

protocol MutationExclusion: Sendable {
    func ranges(in syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]

    func ranges(in source: ParsedSource) -> [Range<AbsolutePosition>]

    func applies(to point: MutationPoint) -> Bool
}

extension MutationExclusion {
    func ranges(in source: ParsedSource) -> [Range<AbsolutePosition>] {
        ranges(in: source.syntax)
    }

    func applies(to point: MutationPoint) -> Bool {
        true
    }

    func filter(_ mutationPoints: [MutationPoint], excluding ranges: [Range<AbsolutePosition>]) -> [MutationPoint] {
        guard !ranges.isEmpty else { return mutationPoints }

        return mutationPoints.filter { point in
            guard applies(to: point) else { return true }
            let position = AbsolutePosition(utf8Offset: point.utf8Offset)
            return !ranges.contains { $0.contains(position) }
        }
    }

    func filter(_ mutationPoints: [MutationPoint], in syntax: SourceFileSyntax) -> [MutationPoint] {
        filter(mutationPoints, excluding: ranges(in: syntax))
    }

    func filter(_ mutationPoints: [MutationPoint], in source: ParsedSource) -> [MutationPoint] {
        filter(mutationPoints, excluding: ranges(in: source))
    }
}
