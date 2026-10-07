import SwiftSyntax
import Testing

@testable import SwiftMutationTesting

@Suite("ParsedSource")
struct ParsedSourceTests {
    @Test("Given a parsed file, when built, then its converter names the file and its scopes are the visitor's")
    func theConverterAndScopesAreBuiltOnce() {
        let code = "struct S {\n    func f() -> Int { 1 + 2 }\n    var g: Int { get { 3 } }\n}"
        let source = makeParsedSource(code, path: "/p/S.swift")
        let visitor = makeTypeScopeVisitor(code)

        #expect(source.locationConverter.location(for: AbsolutePosition(utf8Offset: 0)).file == "/p/S.swift")
        #expect(source.functionScopes.scopes.map(\.bodyStartOffset) == visitor.scopes.map(\.bodyStartOffset))
        #expect(source.functionScopes.scopes.count == 2)
    }

    @Test("Given an operator's visitor, when made for a source, then it uses the source's converter")
    func visitorsShareTheConverter() {
        let source = makeParsedSource("func f() -> Bool { true }")

        let visitor = BooleanLiteralVisitor(source: source)

        #expect(visitor.locationConverter === source.locationConverter)
    }

    @Test("Given a suppressed line, when filtered through the source, then the range is the syntax's")
    func suppressionThroughTheSourceMatchesTheSyntax() {
        let source = makeParsedSource(
            "func f() {\n    // swift-mutation-testing:disable-next-line\n    let a = true\n}"
        )
        let filter = SuppressionFilter()

        #expect(filter.ranges(in: source) == filter.ranges(in: source.syntax))
        #expect(!filter.ranges(in: source).isEmpty)
    }
}
