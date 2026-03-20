import SwiftSyntax

struct FunctionBodyScope {
    let bodyStartOffset: Int
    let bodyEndOffset: Int
    let statementsStartOffset: Int
    let statementsEndOffset: Int
}

final class TypeScopeVisitor: SyntaxVisitor {

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    private(set) var scopes: [FunctionBodyScope] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(body: node.body)
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
        record(body: node.body)
        return .visitChildren
    }

    private func record(body: CodeBlockSyntax?) {
        guard let body else { return }
        scopes.append(
            FunctionBodyScope(
                bodyStartOffset: body.position.utf8Offset,
                bodyEndOffset: body.endPosition.utf8Offset,
                statementsStartOffset: body.statements.position.utf8Offset,
                statementsEndOffset: body.statements.endPosition.utf8Offset
            )
        )
    }

    func isSchematizable(utf8Offset: Int) -> Bool {
        scopes.contains {
            $0.bodyStartOffset <= utf8Offset && utf8Offset < $0.bodyEndOffset
        }
    }

    func innermostScope(containing utf8Offset: Int) -> FunctionBodyScope? {
        scopes
            .filter { $0.bodyStartOffset <= utf8Offset && utf8Offset < $0.bodyEndOffset }
            .min { ($0.bodyEndOffset - $0.bodyStartOffset) < ($1.bodyEndOffset - $1.bodyStartOffset) }
    }
}
