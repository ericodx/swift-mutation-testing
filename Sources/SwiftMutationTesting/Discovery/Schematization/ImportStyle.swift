import SwiftSyntax

enum ImportStyle: String, Sendable, Equatable {
    case implicit
    case explicit

    static func of(_ sources: [ParsedSource]) -> ImportStyle {
        sources.contains { of($0.syntax) == .explicit } ? .explicit : .implicit
    }

    static func of(_ syntax: SourceFileSyntax) -> ImportStyle {
        imports(in: syntax).contains { !$0.modifiers.isEmpty } ? .explicit : .implicit
    }

    static func importsFoundation(_ syntax: SourceFileSyntax) -> Bool {
        imports(in: syntax).contains { $0.path.first?.name.text == "Foundation" }
    }

    private static func imports(in syntax: SourceFileSyntax) -> [ImportDeclSyntax] {
        let hasConditionalBlock = syntax.statements.contains { $0.item.is(IfConfigDeclSyntax.self) }
        let inactive = hasConditionalBlock ? InactiveRegionExtractor().extractInactiveRanges(from: syntax) : []
        return imports(in: syntax.statements, excluding: inactive)
    }

    private static func imports(
        in statements: CodeBlockItemListSyntax,
        excluding inactive: [Range<AbsolutePosition>]
    ) -> [ImportDeclSyntax] {
        statements.flatMap { statement -> [ImportDeclSyntax] in
            if let declaration = statement.item.as(ImportDeclSyntax.self) { return [declaration] }
            guard let block = statement.item.as(IfConfigDeclSyntax.self) else { return [] }
            return block.clauses.flatMap { imports(in: $0, excluding: inactive) }
        }
    }

    private static func imports(
        in clause: IfConfigClauseSyntax,
        excluding inactive: [Range<AbsolutePosition>]
    ) -> [ImportDeclSyntax] {
        guard
            !inactive.contains(where: { $0.contains(clause.position) }),
            case .statements(let nested) = clause.elements
        else { return [] }
        return imports(in: nested, excluding: inactive)
    }
}
