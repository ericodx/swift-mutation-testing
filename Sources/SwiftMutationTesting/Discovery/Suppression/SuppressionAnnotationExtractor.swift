import SwiftSyntax

struct SuppressionAnnotationExtractor: Sendable {
    func extractSuppressedRanges(
        from syntax: SourceFileSyntax, converter: SourceLocationConverter? = nil
    ) -> [Range<AbsolutePosition>] {
        let visitor = SuppressionVisitor(converter: converter ?? SourceLocationConverter(fileName: "", tree: syntax))
        visitor.walk(syntax)
        return visitor.suppressedRanges
    }
}
