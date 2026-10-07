import Testing

@testable import SwiftMutationTesting

@Suite("FunctionBodyScopes")
struct FunctionBodyScopesTests {
    @Test("Given nested and sibling bodies, when every offset is looked up, then the answer is the tightest body")
    func everyOffsetFindsTheTightestBody() {
        let code = """
            let top = 1
            struct S {
                func a() -> Int {
                    func inner() -> Int { 1 + 2 }
                    let x = 3
                    func second() { let y = 4 }
                    return inner() + x
                }
                var b: Int {
                    get { 5 }
                    set { _ = newValue }
                }
                init() {}
            }
            let bottom = 6
            """
        let scopes = makeParsedSource(code).functionScopes

        for offset in 0 ... code.utf8.count {
            let expected = tightest(containing: offset, in: scopes.scopes)
            let found = scopes.innermostScope(containing: offset)
            #expect(found?.bodyStartOffset == expected?.bodyStartOffset, "offset \(offset)")
            #expect(scopes.isSchematizable(utf8Offset: offset) == (expected != nil), "offset \(offset)")
        }
    }

    @Test("Given two bodies that start together, when looked up inside the inner one, then the inner one is found")
    func aSharedStartFindsTheInnerBody() {
        let outer = FunctionBodyScope(
            bodyStartOffset: 10, bodyEndOffset: 50, statementsStartOffset: 11, statementsEndOffset: 49,
            shape: .statements
        )
        let inner = FunctionBodyScope(
            bodyStartOffset: 10, bodyEndOffset: 20, statementsStartOffset: 11, statementsEndOffset: 19,
            shape: .statements
        )
        let scopes = FunctionBodyScopes(scopes: [outer, inner])

        #expect(scopes.innermostScope(containing: 15)?.bodyEndOffset == 20)
        #expect(scopes.innermostScope(containing: 30)?.bodyEndOffset == 50)
        #expect(scopes.innermostScope(containing: 50) == nil)
        #expect(scopes.innermostScope(containing: 9) == nil)
    }

    // MARK: - Private

    private func tightest(containing offset: Int, in scopes: [FunctionBodyScope]) -> FunctionBodyScope? {
        scopes
            .filter { $0.bodyStartOffset <= offset && offset < $0.bodyEndOffset }
            .min { ($0.bodyEndOffset - $0.bodyStartOffset) < ($1.bodyEndOffset - $1.bodyStartOffset) }
    }
}
