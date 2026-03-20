import SwiftSyntax

struct SuppressionAnnotationExtractor {
    func extractSuppressedRanges(from syntax: SourceFileSyntax) -> [Range<AbsolutePosition>] {
        let visitor = SuppressionVisitor()
        visitor.walk(syntax)
        return visitor.suppressedRanges
    }
}
