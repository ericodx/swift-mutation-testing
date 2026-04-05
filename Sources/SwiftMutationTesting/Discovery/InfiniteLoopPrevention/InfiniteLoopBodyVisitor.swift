import SwiftSyntax

final class InfiniteLoopBodyVisitor: SyntaxVisitor {

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    private(set) var loopBodyRanges: [Range<AbsolutePosition>] = []

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        loopBodyRanges.append(node.body.position ..< node.body.endPosition)
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        loopBodyRanges.append(node.body.position ..< node.body.endPosition)
        return .visitChildren
    }
}
