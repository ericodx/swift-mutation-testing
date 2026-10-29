import SwiftSyntax

struct LoopConditions: Sendable {
    let ranges: [Range<AbsolutePosition>]

    init(in syntax: SourceFileSyntax) {
        let visitor = LoopConditionVisitor()
        visitor.walk(syntax)
        ranges = visitor.ranges
    }

    func contains(utf8Offset: Int) -> Bool {
        let position = AbsolutePosition(utf8Offset: utf8Offset)
        return ranges.contains { $0.contains(position) }
    }
}

private final class LoopConditionVisitor: SyntaxVisitor {
    private(set) var ranges: [Range<AbsolutePosition>] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        ranges.append(node.conditions.position ..< node.conditions.endPosition)
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        ranges.append(node.condition.position ..< node.condition.endPosition)
        return .visitChildren
    }
}
