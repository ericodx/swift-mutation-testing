import Testing

@testable import SwiftMutationTesting

@Suite("TypeScopeVisitor")
struct TypeScopeVisitorTests {
    private func makeVisitor(_ code: String) -> TypeScopeVisitor {
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)
        return visitor
    }

    @Test("Given function with body, when walked, then records one scope")
    func functionWithBodyRecordsOneScope() {
        let visitor = makeVisitor("func f() { let x = 1 }")
        #expect(visitor.scopes.count == 1)
    }

    @Test("Given protocol function requirement without body, when walked, then records no scope")
    func functionWithoutBodyRecordsNoScope() {
        let visitor = makeVisitor("protocol P { func f() }")
        #expect(visitor.scopes.isEmpty)
    }

    @Test("Given two functions, when walked, then records two scopes")
    func twoFunctionsRecordTwoScopes() {
        let visitor = makeVisitor("func f() { } func g() { }")
        #expect(visitor.scopes.count == 2)
    }

    @Test("Given nested function, when walked, then records two scopes")
    func nestedFunctionRecordsTwoScopes() {
        let code = "func outer() { func inner() { let x = 1 } }"
        let visitor = makeVisitor(code)
        #expect(visitor.scopes.count == 2)
    }

    @Test("Given initializer with body, when walked, then records one scope")
    func initializerRecordsScope() {
        let visitor = makeVisitor("struct S { init() { let x = 1 } }")
        #expect(visitor.scopes.count == 1)
    }

    @Test("Given mutation offset inside function body, when checked, then isSchematizable returns true")
    func offsetInsideFunctionBodyIsSchematizable() {
        let code = "func f() { let x = true }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(visitor.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given mutation at file scope, when checked, then isSchematizable returns false")
    func offsetAtFileScopeIsNotSchematizable() {
        let code = "let x = true"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(!visitor.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given computed property with implicit getter, when walked, then mutation inside is not schematizable")
    func computedPropertyImplicitGetterIsNotSchematizable() {
        let code = "struct S { var x: Bool { return true } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(!visitor.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given computed property with explicit getter, when walked, then mutation inside is schematizable")
    func computedPropertyExplicitGetterIsSchematizable() {
        let code = "struct S { var x: Bool { get { return true } } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(visitor.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given mutation inside global-scope closure, when checked, then isSchematizable returns false")
    func mutationInsideGlobalScopeClosureIsNotSchematizable() {
        let code = "let compute: () -> Bool = { return true }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(!visitor.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given nested function, when innermostScope queried, then returns smallest containing scope")
    func innermostScopeReturnsSmallestContainingScope() {
        let code = "func outer() { func inner() { let x = 1 } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(
            in: makeParsedSource("func outer() { func inner() { let x = true } }")
        )[0]

        let innerSource = makeParsedSource("func outer() { func inner() { let x = true } }")
        let innerVisitor = TypeScopeVisitor()
        innerVisitor.walk(innerSource.syntax)

        guard let innerMutation = BooleanLiteralReplacement().mutations(in: innerSource).first,
            let scope = innerVisitor.innermostScope(containing: innerMutation.utf8Offset)
        else {
            Issue.record("Expected a mutation and scope")
            return
        }

        let outerScope = innerVisitor.scopes.max {
            ($0.bodyEndOffset - $0.bodyStartOffset) < ($1.bodyEndOffset - $1.bodyStartOffset)
        }!

        #expect(scope.bodyStartOffset > outerScope.bodyStartOffset)
    }
}
