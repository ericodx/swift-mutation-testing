import SwiftSyntax

struct NegateConditional: MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint] {
        let visitor = NegateConditionalVisitor(source: source)
        visitor.walk(source.syntax)
        return visitor.mutations
    }
}

private final class NegateConditionalVisitor: MutationSyntaxVisitor {
    override func visit(_ node: ConditionElementSyntax) -> SyntaxVisitorContinueKind {
        guard case .expression(let expr) = node.condition,
            let firstToken = expr.firstToken(viewMode: .sourceAccurate)
        else {
            return .visitChildren
        }

        let originalText = expr.trimmedDescription
        let location = firstToken.startLocation(converter: locationConverter)

        mutations.append(
            MutationPoint(
                operatorIdentifier: "NegateConditional",
                filePath: filePath,
                line: location.line,
                column: location.column,
                utf8Offset: firstToken.positionAfterSkippingLeadingTrivia.utf8Offset,
                originalText: originalText,
                mutatedText: "!(\(originalText))",
                replacement: .wrapWithNegation,
                description: "\(originalText) → !(\(originalText))"
            )
        )

        return .visitChildren
    }
}
