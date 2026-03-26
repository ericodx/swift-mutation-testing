import SwiftSyntax

final class ArithmeticOperatorVisitor: MutationSyntaxVisitor {
    private static let replacementTable: [String: String] = [
        "+": "-",
        "-": "+",
        "*": "/",
        "/": "*",
        "%": "*",
    ]

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        guard case .binaryOperator(let operatorText) = token.tokenKind,
            let replacement = Self.replacementTable[operatorText]
        else {
            return .visitChildren
        }

        if (operatorText == "+" || operatorText == "-") && hasStringLiteralOperand(around: token) {
            return .visitChildren
        }

        let location = token.startLocation(converter: locationConverter)

        mutations.append(
            MutationPoint(
                operatorIdentifier: "ArithmeticOperatorReplacement",
                filePath: filePath,
                line: location.line,
                column: location.column,
                utf8Offset: token.positionAfterSkippingLeadingTrivia.utf8Offset,
                originalText: operatorText,
                mutatedText: replacement,
                replacement: .binaryOperator,
                description: "\(operatorText) → \(replacement)"
            )
        )

        return .visitChildren
    }

    private func hasStringLiteralOperand(around token: TokenSyntax) -> Bool {
        guard let operatorExpr = token.parent?.as(BinaryOperatorExprSyntax.self),
            let elements = operatorExpr.parent?.as(ExprListSyntax.self)
        else { return false }

        let items = Array(elements)

        guard let operatorIndex = items.firstIndex(where: { $0.position == operatorExpr.position })
        else { return false }

        let leftIndex = operatorIndex - 1
        let rightIndex = operatorIndex + 1

        if leftIndex >= 0 && items[leftIndex].is(StringLiteralExprSyntax.self) {
            return true
        }

        if rightIndex < items.count && items[rightIndex].is(StringLiteralExprSyntax.self) {
            return true
        }

        return false
    }
}
