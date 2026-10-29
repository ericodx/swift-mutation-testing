import SwiftSyntax

struct ParsedSource: Sendable {
    let file: SourceFile
    let syntax: SourceFileSyntax
    let locationConverter: SourceLocationConverter
    let functionScopes: FunctionBodyScopes
    let loopConditions: LoopConditions

    init(file: SourceFile, syntax: SourceFileSyntax) {
        self.file = file
        self.syntax = syntax
        locationConverter = SourceLocationConverter(fileName: file.path, tree: syntax)
        let visitor = TypeScopeVisitor()
        visitor.walk(syntax)
        functionScopes = visitor.functionScopes
        loopConditions = LoopConditions(in: syntax)
    }
}
