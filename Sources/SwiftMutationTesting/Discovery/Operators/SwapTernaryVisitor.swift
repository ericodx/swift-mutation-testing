import SwiftSyntax

final class SwapTernaryVisitor: MutationSyntaxVisitor {
    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        guard let elements = node.parent?.as(ExprListSyntax.self).map(Array.init)
        else { return .visitChildren }

        guard let ternaryIndex = elements.firstIndex(where: { $0.position == node.position }),
            ternaryIndex > 0,
            ternaryIndex + 1 < elements.count
        else { return .visitChildren }

        let conditionExpr = elements[ternaryIndex - 1]
        let thenExpr = node.thenExpression
        let elseExpr = elements[ternaryIndex + 1]

        guard let firstToken = conditionExpr.firstToken(viewMode: .sourceAccurate)
        else { return .visitChildren }

        let condition = conditionExpr.trimmedDescription
        let location = firstToken.startLocation(converter: locationConverter)

        mutations.append(
            MutationPoint(
                operatorIdentifier: "SwapTernary",
                filePath: filePath,
                line: location.line,
                column: location.column,
                utf8Offset: firstToken.positionAfterSkippingLeadingTrivia.utf8Offset,
                originalText: condition,
                mutatedText: "\(condition) ? \(elseExpr.trimmedDescription) : \(thenExpr.trimmedDescription)",
                replacement: .swapTernary,
                description: "swap ternary branches"
            )
        )

        return .visitChildren
    }
}
