import SwiftSyntax

struct SuppressionFilter: MutationExclusion {
    private let extractor = SuppressionAnnotationExtractor()

    func ranges(in syntax: SourceFileSyntax) -> [Range<AbsolutePosition>] {
        extractor.extractSuppressedRanges(from: syntax)
    }

    func ranges(in source: ParsedSource) -> [Range<AbsolutePosition>] {
        extractor.extractSuppressedRanges(from: source.syntax, converter: source.locationConverter)
    }
}
