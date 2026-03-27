import SwiftSyntax

final class SuppressionVisitor: SyntaxVisitor {

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    private(set) var suppressedRanges: [Range<AbsolutePosition>] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSuppressed(node.attributes) {
            suppressedRanges.append(node.position ..< node.endPosition)
            return .skipChildren
        }

        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSuppressed(node.attributes) {
            suppressedRanges.append(node.position ..< node.endPosition)
            return .skipChildren
        }

        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSuppressed(node.attributes) {
            suppressedRanges.append(node.position ..< node.endPosition)
            return .skipChildren
        }

        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSuppressed(node.attributes) {
            suppressedRanges.append(node.position ..< node.endPosition)
            return .skipChildren
        }

        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSuppressed(node.attributes) {
            suppressedRanges.append(node.position ..< node.endPosition)
            return .skipChildren
        }

        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSuppressed(node.attributes) {
            suppressedRanges.append(node.position ..< node.endPosition)
            return .skipChildren
        }

        return .visitChildren
    }

    override func visit(_ _: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .visitChildren
    }

    private func isSuppressed(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case .attribute(let attr) = element,
                let identType = attr.attributeName.as(IdentifierTypeSyntax.self)
            else {
                return false
            }

            return identType.name.text == "SwiftMutationTestingDisabled"
        }
    }
}
