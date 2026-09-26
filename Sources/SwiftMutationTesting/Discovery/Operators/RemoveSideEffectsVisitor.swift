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

        guard !isSoleStatementOfBody(node) else {
            return .visitChildren
        }

        guard let firstToken = node.firstToken(viewMode: .sourceAccurate)
        else { return .visitChildren }

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

    private func isSoleStatementOfBody(_ node: CodeBlockItemSyntax) -> Bool {
        guard let list = node.parent?.as(CodeBlockItemListSyntax.self), list.count == 1,
            let owner = list.parent
        else { return false }

        if owner.is(ClosureExprSyntax.self) || owner.is(AccessorBlockSyntax.self)
            || owner.is(SwitchCaseSyntax.self)
        {
            return true
        }

        guard let block = owner.as(CodeBlockSyntax.self), let holder = block.parent
        else { return false }

        return holder.is(FunctionDeclSyntax.self)
            || holder.is(InitializerDeclSyntax.self)
            || holder.is(DeinitializerDeclSyntax.self)
            || holder.is(AccessorDeclSyntax.self)
    }
}
