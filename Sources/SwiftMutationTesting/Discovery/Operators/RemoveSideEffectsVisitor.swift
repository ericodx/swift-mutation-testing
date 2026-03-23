import SwiftSyntax

final class RemoveSideEffectsVisitor: MutationSyntaxVisitor {
    private static let deniedCallee: Set<String> = [
        "print", "debugPrint", "assert", "assertionFailure",
        "precondition", "preconditionFailure", "fatalError",
    ]

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        guard case .expr(let expr) = node.item,
            let callExpr = expr.as(FunctionCallExprSyntax.self)
        else {
            return .visitChildren
        }

        let callee = callExpr.calledExpression.trimmedDescription

        guard !Self.deniedCallee.contains(callee) else {
            return .visitChildren
        }

        guard let firstToken = node.firstToken(viewMode: .sourceAccurate) else {
            return .visitChildren
        }

        let location = firstToken.startLocation(converter: locationConverter)

        mutations.append(
            MutationPoint(
                operatorIdentifier: "RemoveSideEffects",
                filePath: filePath,
                line: location.line,
                column: location.column,
                utf8Offset: firstToken.positionAfterSkippingLeadingTrivia.utf8Offset,
                originalText: expr.trimmedDescription,
                mutatedText: "",
                replacement: .removeStatement,
                description: "remove \(callee)()"
            )
        )

        return .visitChildren
    }
}
