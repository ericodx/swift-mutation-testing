import Testing

@testable import SwiftMutationTesting

@Suite("TypeScopeVisitor")
struct TypeScopeVisitorTests {
    @Test("Given function with body, when walked, then records one scope")
    func functionWithBodyRecordsOneScope() {
        let visitor = makeTypeScopeVisitor("func f() { let x = 1 }")
        #expect(visitor.scopes.count == 1)
    }

    @Test("Given protocol function requirement without body, when walked, then records no scope")
    func functionWithoutBodyRecordsNoScope() {
        let visitor = makeTypeScopeVisitor("protocol P { func f() }")
        #expect(visitor.scopes.isEmpty)
    }

    @Test("Given two functions, when walked, then records two scopes")
    func twoFunctionsRecordTwoScopes() {
        let visitor = makeTypeScopeVisitor("func f() { } func g() { }")
        #expect(visitor.scopes.count == 2)
    }

    @Test("Given nested function, when walked, then records two scopes")
    func nestedFunctionRecordsTwoScopes() {
        let code = "func outer() { func inner() { let x = 1 } }"
        let visitor = makeTypeScopeVisitor(code)
        #expect(visitor.scopes.count == 2)
    }

    @Test("Given initializer with body, when walked, then records one scope")
    func initializerRecordsScope() {
        let visitor = makeTypeScopeVisitor("struct S { init() { let x = 1 } }")
        #expect(visitor.scopes.count == 1)
    }

    @Test("Given mutation offset inside function body, when checked, then isSchematizable returns true")
    func offsetInsideFunctionBodyIsSchematizable() {
        let code = "func f() { let x = true }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(visitor.functionScopes.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given mutation at file scope, when checked, then isSchematizable returns false")
    func offsetAtFileScopeIsNotSchematizable() {
        let code = "let x = true"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(!visitor.functionScopes.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given computed property with implicit getter, when walked, then mutation inside is not schematizable")
    func computedPropertyImplicitGetterIsNotSchematizable() {
        let code = "struct S { var x: Bool { return true } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(!visitor.functionScopes.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given computed property with explicit getter, when walked, then mutation inside is schematizable")
    func computedPropertyExplicitGetterIsSchematizable() {
        let code = "struct S { var x: Bool { get { return true } } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(visitor.functionScopes.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given mutation inside global-scope closure, when checked, then isSchematizable returns false")
    func mutationInsideGlobalScopeClosureIsNotSchematizable() {
        let code = "let compute: () -> Bool = { return true }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        #expect(!visitor.functionScopes.isSchematizable(utf8Offset: mutation.utf8Offset))
    }

    @Test("Given deinitializer with body, when walked, then records one scope")
    func deinitializerRecordsScope() {
        let visitor = makeTypeScopeVisitor("class C { deinit { let x = 1 } }")
        #expect(visitor.scopes.count == 1)
    }

    @Test("Given computed property with explicit setter, when walked, then mutation inside is schematizable")
    func computedPropertyExplicitSetterIsSchematizable() {
        let code = "class C { var x: Int = 0 { didSet { let enabled = true; _ = enabled } } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let insideBody = mutations.first { visitor.functionScopes.isSchematizable(utf8Offset: $0.utf8Offset) }
        #expect(insideBody != nil)
    }

    @Test("Given offset outside all scopes, when innermostScope queried, then returns nil")
    func innermostScopeReturnsNilForOffsetOutsideAllScopes() {
        let visitor = makeTypeScopeVisitor("func f() { let x = 1 }")
        #expect(visitor.functionScopes.innermostScope(containing: 99999) == nil)
    }

    @Test("Given nested function, when innermostScope queried, then returns smallest containing scope")
    func innermostScopeReturnsSmallestContainingScope() {
        let code = "func outer() { func inner() { let x = 1 } }"
        let source = makeParsedSource(code)
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        let innerSource = makeParsedSource("func outer() { func inner() { let x = true } }")
        let innerVisitor = TypeScopeVisitor()
        innerVisitor.walk(innerSource.syntax)

        guard let innerMutation = BooleanLiteralReplacement().mutations(in: innerSource).first,
            let scope = innerVisitor.functionScopes.innermostScope(containing: innerMutation.utf8Offset)
        else {
            Issue.record("Expected a mutation and scope")
            return
        }

        let outerScope = innerVisitor.scopes.max {
            ($0.bodyEndOffset - $0.bodyStartOffset) < ($1.bodyEndOffset - $1.bodyStartOffset)
        }!

        #expect(scope.bodyStartOffset > outerScope.bodyStartOffset)
    }

    @Test(
        "Given a body, when walked, then its shape says whether it is one expression, one conditional or statements",
        arguments: [
            ("func f(_ a: Int, _ b: Int) -> Int { a + b }", FunctionBodyShape.expression),
            ("func f() { print(1) }", .statements),
            ("func f() -> Int { return 1 }", .statements),
            ("func f() -> Int { let x = 1; return x }", .statements),
            ("func f() {}", .statements),
            ("func f(_ c: Bool) -> Int { if c { 1 } else { 2 } }", .conditional(returnsValue: true)),
            ("func f(_ n: Int) -> String { switch n { default: \"n\" } }", .conditional(returnsValue: true)),
            ("func f(_ c: Bool) { if c { print(1) } else { print(2) } }", .conditional(returnsValue: false)),
            ("func f(_ c: Bool) -> Void { if c { print(1) } else { print(2) } }", .conditional(returnsValue: false)),
            ("func f(_ c: Bool) -> () { if c { print(1) } else { print(2) } }", .conditional(returnsValue: false)),
            ("func f(_ c: Bool) { if c { print(1) } }", .statements),
            ("struct S { var v: Int { get { if true { 1 } else { 2 } } } }", .conditional(returnsValue: true)),
            ("struct S { var v: Int { get { 1 } } }", .expression),
            (
                "struct S { var v: Int { get { 1 } set { if true { print(newValue) } else { print(0) } } } }",
                .conditional(returnsValue: false)
            ),
            ("struct S { var x = 0; init(c: Bool) { if c { x = 1 } } }", .statements),
            ("struct S { init() {}; init(c: Bool) { self.init() } }", .statements),
            ("struct S { var v: Int { get { 1 } set { print(newValue) } } }", .statements),
            ("func f(_ n: Int) -> Int { switch n { case 0: return 1\ndefault: return 2 } }", .statements),
            ("func f(_ c: Bool) -> Int { if c { return 1 } else { return 2 } }", .statements),
            ("func f(_ c: Bool) -> Int { if c { 1 } else if !c { 2 } else { 3 } }", .conditional(returnsValue: true)),
            (
                "func f(_ n: Int) -> Int { switch n { case 0: 1\ndefault: if n > 1 { 2 } else { 3 } } }",
                .conditional(returnsValue: true)
            ),
            ("func f(_ n: Int) -> Int { switch n { case 0: 1\ndefault: let x = 2; return x } }", .statements),
            ("func f(_ c: Bool) -> Int { if c { let x = 1 } else { 2 } }", .statements),
            ("func f(_ n: Int) -> Int { switch n {\n#if DEBUG\ncase 0: 1\n#endif\ndefault: 2\n} }", .statements),
        ]
    )
    func bodyShapeIsRecorded(code: String, expected: FunctionBodyShape) {
        let visitor = makeTypeScopeVisitor(code)

        #expect(visitor.scopes.last?.shape == expected)
    }
}
