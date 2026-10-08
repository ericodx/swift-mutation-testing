import SwiftSyntax

final class TypeScopeVisitor: SyntaxVisitor {

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    private(set) var scopes: [FunctionBodyScope] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(body: node.body, returnsValue: Self.returnsValue(node.signature.returnClause))
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(body: node.body)
        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(body: node.body)
        return .visitChildren
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(body: node.body, returnsValue: node.accessorSpecifier.tokenKind == .keyword(.get))
        return .visitChildren
    }

    private func record(body: CodeBlockSyntax?, returnsValue: Bool = false) {
        guard let body else { return }
        scopes.append(
            FunctionBodyScope(
                bodyStartOffset: body.position.utf8Offset,
                bodyEndOffset: body.endPosition.utf8Offset,
                statementsStartOffset: body.statements.position.utf8Offset,
                statementsEndOffset: body.statements.endPosition.utf8Offset,
                shape: Self.shape(of: body.statements, returnsValue: returnsValue)
            )
        )
    }

    private static func shape(of statements: CodeBlockItemListSyntax, returnsValue: Bool) -> FunctionBodyShape {
        guard statements.count == 1, let item = statements.first?.item else { return .statements }

        let expression: ExprSyntax?
        switch item {
        case .expr(let expr): expression = expr
        case .stmt(let stmt): expression = stmt.as(ExpressionStmtSyntax.self)?.expression
        case .decl: expression = nil
        }

        guard let expression else { return .statements }

        if expression.is(IfExprSyntax.self) || expression.is(SwitchExprSyntax.self) {
            return isExpression(expression) ? .conditional(returnsValue: returnsValue) : .statements
        }

        return returnsValue ? .expression : .statements
    }

    private static func isExpression(_ expression: ExprSyntax) -> Bool {
        if let switchExpr = expression.as(SwitchExprSyntax.self) {
            return switchExpr.cases.allSatisfy { element in
                guard case .switchCase(let switchCase) = element else { return false }
                return isSingleExpression(switchCase.statements)
            }
        }

        guard let ifExpr = expression.as(IfExprSyntax.self), isSingleExpression(ifExpr.body.statements) else {
            return false
        }

        switch ifExpr.elseBody {
        case .codeBlock(let block): return isSingleExpression(block.statements)
        case .ifExpr(let nested): return isExpression(ExprSyntax(nested))
        case nil: return false
        }
    }

    private static func isSingleExpression(_ statements: CodeBlockItemListSyntax) -> Bool {
        guard statements.count == 1, let item = statements.first?.item else { return false }

        switch item {
        case .expr(let expr):
            return expr.is(IfExprSyntax.self) || expr.is(SwitchExprSyntax.self) ? isExpression(expr) : true
        case .stmt(let stmt):
            return stmt.as(ExpressionStmtSyntax.self).map { isExpression($0.expression) } ?? false
        case .decl:
            return false
        }
    }

    private static func returnsValue(_ returnClause: ReturnClauseSyntax?) -> Bool {
        guard let type = returnClause?.type.trimmedDescription else { return false }
        return type != "Void" && type != "()"
    }

    var functionScopes: FunctionBodyScopes {
        FunctionBodyScopes(scopes: scopes)
    }
}
