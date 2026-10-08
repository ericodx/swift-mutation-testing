import SwiftOperators
import SwiftParser
import SwiftSyntax

struct ActivationInstrumenter: Sendable {
    let importStyle: ImportStyle

    func instrument(_ mutant: MutantDescriptor) -> String? {
        guard let content = mutant.mutatedSourceContent else { return nil }

        let syntax = Parser.parse(source: content)
        let folded = OperatorTable.standardOperators.foldAll(syntax) { _ in }
        let length = mutant.mutatedText.utf8.count

        guard
            let token = folded.token(at: AbsolutePosition(utf8Offset: mutant.utf8Offset)),
            !Self.isInForbiddenContext(token)
        else { return nil }

        let instrumented: String?
        if mutant.replacementKind == .removeStatement {
            instrumented = UTF8Splice.inserting(
                SupportDeclarations.activationCall(for: mutant.filePath), at: mutant.utf8Offset, in: content
            )
        } else {
            guard let expression = Self.smallestWrappable(around: token, from: mutant.utf8Offset, length: length)
            else { return nil }
            instrumented = Self.wrap(
                expression, in: content, with: SupportDeclarations.activatingCall(for: mutant.filePath)
            )
        }

        return instrumented.map {
            SupportDeclarations.appended(to: $0, path: mutant.filePath, syntax: syntax, style: importStyle)
        }
    }

    // MARK: - Private

    private static func smallestWrappable(around token: TokenSyntax, from offset: Int, length: Int) -> ExprSyntax? {
        var node: Syntax? = Syntax(token)
        while let current = node {
            if let expression = current.as(ExprSyntax.self), isWrappable(expression),
                expression.positionAfterSkippingLeadingTrivia.utf8Offset <= offset,
                expression.endPositionBeforeTrailingTrivia.utf8Offset >= offset + length
            {
                return expression
            }
            if current.is(CodeBlockItemSyntax.self) || current.is(MemberBlockItemSyntax.self) { return nil }
            node = current.parent
        }
        return nil
    }

    private static func isWrappable(_ expression: ExprSyntax) -> Bool {
        let unwrappable: [any ExprSyntaxProtocol.Type] = [
            BinaryOperatorExprSyntax.self, AssignmentExprSyntax.self, ArrowExprSyntax.self,
            UnresolvedTernaryExprSyntax.self, UnresolvedIsExprSyntax.self, UnresolvedAsExprSyntax.self,
            InOutExprSyntax.self, TypeExprSyntax.self, PatternExprSyntax.self, DiscardAssignmentExprSyntax.self,
        ]
        return !unwrappable.contains { expression.is($0) }
    }

    private static func isInForbiddenContext(_ token: TokenSyntax) -> Bool {
        var child = Syntax(token)
        var node = token.parent
        while let current = node {
            if current.is(AttributeSyntax.self) || current.is(MacroExpansionExprSyntax.self)
                || current.is(MacroExpansionDeclSyntax.self) || current.is(EnumCaseElementSyntax.self)
            {
                return true
            }
            if let clause = current.as(IfConfigClauseSyntax.self), let condition = clause.condition,
                Syntax(condition).id == child.id
            {
                return true
            }
            child = current
            node = current.parent
        }
        return false
    }

    private static func wrap(_ expression: ExprSyntax, in content: String, with call: String) -> String? {
        let start = expression.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = expression.endPositionBeforeTrailingTrivia.utf8Offset
        let wrapped = "\(call)(\(expression.trimmedDescription))"
        return UTF8Splice.replacing(from: start, to: end, in: content, with: wrapped)
    }
}
