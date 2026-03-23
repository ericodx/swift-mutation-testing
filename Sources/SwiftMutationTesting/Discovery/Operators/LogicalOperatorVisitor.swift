import SwiftSyntax

final class LogicalOperatorVisitor: MutationSyntaxVisitor {
    private static let replacementTable: [String: String] = [
        "&&": "||",
        "||": "&&",
    ]

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        guard case .binaryOperator(let operatorText) = token.tokenKind,
            let replacement = Self.replacementTable[operatorText]
        else {
            return .visitChildren
        }

        let location = token.startLocation(converter: locationConverter)

        mutations.append(
            MutationPoint(
                operatorIdentifier: "LogicalOperatorReplacement",
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
}
