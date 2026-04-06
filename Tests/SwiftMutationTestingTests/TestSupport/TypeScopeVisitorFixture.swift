import SwiftSyntax

@testable import SwiftMutationTesting

func makeTypeScopeVisitor(_ code: String) -> TypeScopeVisitor {
    let source = makeParsedSource(code)
    let visitor = TypeScopeVisitor()
    visitor.walk(source.syntax)
    return visitor
}
