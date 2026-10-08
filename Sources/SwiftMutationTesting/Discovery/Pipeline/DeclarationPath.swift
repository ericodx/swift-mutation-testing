import SwiftSyntax

enum DeclarationPath {
    static let topLevel = "<top-level>"

    static func of(utf8Offset: Int, in syntax: SourceFileSyntax) -> String {
        guard let token = syntax.token(at: AbsolutePosition(utf8Offset: utf8Offset)) else { return topLevel }

        let names = sequence(first: Syntax(token), next: \.parent).compactMap(name(of:))

        return names.isEmpty ? topLevel : names.reversed().joined(separator: ".")
    }

    private static func name(of node: Syntax) -> String? {
        if let decl = node.as(FunctionDeclSyntax.self) {
            return decl.name.text + labels(decl.signature.parameterClause.parameters)
        }
        if let decl = node.as(InitializerDeclSyntax.self) {
            return "init" + labels(decl.signature.parameterClause.parameters)
        }
        if let decl = node.as(SubscriptDeclSyntax.self) {
            return "subscript" + labels(decl.parameterClause.parameters)
        }
        if node.is(DeinitializerDeclSyntax.self) {
            return "deinit"
        }
        if let decl = node.as(AccessorDeclSyntax.self) {
            return decl.accessorSpecifier.text
        }
        if let decl = node.as(VariableDeclSyntax.self) {
            return decl.bindings.map { $0.pattern.trimmedDescription }.joined(separator: ",")
        }
        return typeName(of: node)
    }

    private static func typeName(of node: Syntax) -> String? {
        if let decl = node.as(ClassDeclSyntax.self) { return decl.name.text }
        if let decl = node.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = node.as(EnumDeclSyntax.self) { return decl.name.text }
        if let decl = node.as(ActorDeclSyntax.self) { return decl.name.text }
        if let decl = node.as(ExtensionDeclSyntax.self) { return decl.extendedType.trimmedDescription }
        return nil
    }

    private static func labels(_ parameters: FunctionParameterListSyntax) -> String {
        "(" + parameters.map { $0.firstName.text + ":" }.joined() + ")"
    }
}
