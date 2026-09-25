import SwiftSyntax

final class SwapTernaryVisitor: MutationSyntaxVisitor {
    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        guard let elements = node.parent?.as(ExprListSyntax.self).map(Array.init)
        else { return .visitChildren }

        guard let ternaryIndex = elements.firstIndex(where: { $0.position == node.position }),
            ternaryIndex > 0,
            ternaryIndex + 1 < elements.count
        else { return .visitChildren }

        let conditionStart = conditionStartIndex(in: elements, before: ternaryIndex)
        let conditionElements = elements[conditionStart ..< ternaryIndex]
        let elseElements = elements[(ternaryIndex + 1)...]

        guard let firstToken = conditionElements.first?.firstToken(viewMode: .sourceAccurate)
        else { return .visitChildren }

        let condition = joined(conditionElements)
        let thenText = node.thenExpression.trimmedDescription
        let elseText = joined(elseElements)

        guard thenText != elseText else { return .visitChildren }

        let original = joined(elements[conditionStart...])
        let location = firstToken.startLocation(converter: locationConverter)

        mutations.append(
            MutationPoint(
                operatorIdentifier: "SwapTernary",
                filePath: filePath,
                line: location.line,
                column: location.column,
                utf8Offset: firstToken.positionAfterSkippingLeadingTrivia.utf8Offset,
                originalText: original,
                mutatedText: "\(condition) ? \(elseText) : \(thenText)",
                replacement: .swapTernary,
                description: "swap ternary branches"
            )
        )

        return .visitChildren
    }

    private func conditionStartIndex(in elements: [ExprSyntax], before ternaryIndex: Int) -> Int {
        for index in stride(from: ternaryIndex - 1, through: 0, by: -1)
        where elements[index].is(UnresolvedTernaryExprSyntax.self) {
            return index + 1
        }
        return 0
    }

    private func joined(_ elements: ArraySlice<ExprSyntax>) -> String {
        elements.map(\.description).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
