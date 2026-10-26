import SwiftSyntax

final class BooleanLiteralVisitor: MutationSyntaxVisitor, OperatorVisitor {
    static let operatorIdentifier = "BooleanLiteralReplacement"
    static let summary = "Boolean literal replacement"
    static let explanation =
        "Replaces true with false and false with true. A survivor usually means a flag's effect is not asserted."

    override func visit(_ node: BooleanLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        guard !isInExhaustiveBooleanSwitchPattern(node) else {
            return .visitChildren
        }

        let token = node.literal
        let isTrue = token.tokenKind == .keyword(.true)
        let originalText = token.trimmedDescription
        let mutatedText = isTrue ? "false" : "true"

        mutations.append(
            MutationPoint(
                operatorIdentifier: Self.operatorIdentifier,
                filePath: filePath,
                line: token.startLocation(converter: locationConverter).line,
                column: token.startLocation(converter: locationConverter).column,
                utf8Offset: token.positionAfterSkippingLeadingTrivia.utf8Offset,
                originalText: originalText,
                mutatedText: mutatedText,
                replacement: .booleanLiteral,
                description: "\(originalText) → \(mutatedText)"
            )
        )

        return .visitChildren
    }

    private func isInExhaustiveBooleanSwitchPattern(_ node: BooleanLiteralExprSyntax) -> Bool {
        guard let item = node.ancestorOrSelf(mapping: { $0.as(SwitchCaseItemSyntax.self) }),
            node.position >= item.pattern.position, node.endPosition <= item.pattern.endPosition,
            let switchExpr = item.ancestorOrSelf(mapping: { $0.as(SwitchExprSyntax.self) })
        else { return false }

        for element in switchExpr.cases {
            guard let switchCase = element.as(SwitchCaseSyntax.self),
                let label = switchCase.label.as(SwitchCaseLabelSyntax.self),
                label.caseItems.allSatisfy({ isBooleanLiteralPattern($0.pattern) })
            else { return false }
        }

        return true
    }

    private func isBooleanLiteralPattern(_ pattern: PatternSyntax) -> Bool {
        guard let expr = pattern.as(ExpressionPatternSyntax.self)?.expression else { return false }
        return literalCount(in: expr).map { $0 > 0 } ?? false
    }

    private func literalCount(in expr: ExprSyntax) -> Int? {
        if expr.is(BooleanLiteralExprSyntax.self) { return 1 }
        if expr.is(DiscardAssignmentExprSyntax.self) { return 0 }
        guard let tuple = expr.as(TupleExprSyntax.self) else { return nil }

        var count = 0
        for element in tuple.elements {
            guard element.label == nil, let elementCount = literalCount(in: element.expression) else { return nil }
            count += elementCount
        }
        return count
    }
}
