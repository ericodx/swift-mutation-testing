import SwiftSyntax

struct InfiniteLoopBodyExtractor: Sendable {
    func extractLoopBodyRanges(from syntax: SourceFileSyntax) -> [Range<AbsolutePosition>] {
        let visitor = InfiniteLoopBodyVisitor()
        visitor.walk(syntax)
        return visitor.loopBodyRanges
    }
}
