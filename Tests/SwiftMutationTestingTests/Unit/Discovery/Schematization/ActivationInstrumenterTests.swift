import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftMutationTesting

@Suite("ActivationInstrumenter")
struct ActivationInstrumenterTests {
    private static let path = "/p/Sources/Config.swift"
    private let wrap = SupportDeclarations.activatingCall(for: path)
    private let activated = SupportDeclarations.activationCall(for: path)

    @Test("Given an operator in a stored property initializer, when instrumented, then its whole expression is wrapped")
    func wrapsTheOperatorsExpression() throws {
        let result = try #require(instrument("struct C {\n    var limit = 10 - 1\n}", at: "-"))

        #expect(result.hasPrefix("struct C {\n    var limit = \(wrap)(10 - 1)\n}"))
    }

    @Test("Given an operator inside a longer expression, when instrumented, then only its operands are wrapped")
    func wrapsOnlyTheOperatorsOwnOperands() throws {
        let result = try #require(instrument("let ok = flag && count - 1 > 2", at: "-"))

        #expect(result.hasPrefix("let ok = flag && \(wrap)(count - 1) > 2"))
    }

    @Test("Given a literal default parameter value, when instrumented, then the literal is wrapped")
    func wrapsADefaultParameterValue() throws {
        let result = try #require(instrument("func f(x: Bool = false) {}", at: "false", kind: .booleanLiteral))

        #expect(result.hasPrefix("func f(x: Bool = \(wrap)(false)) {}"))
    }

    @Test("Given a mutation inside a closure, when instrumented, then the wrapper stays inside the closure")
    func keepsTheWrapperInsideAClosure() throws {
        let result = try #require(instrument("let f: (Int) -> Int = { $0 * 2 }", at: "*"))

        #expect(result.hasPrefix("let f: (Int) -> Int = { \(wrap)($0 * 2) }"))
    }

    @Test("Given a negated condition, when instrumented, then the negation is wrapped whole")
    func wrapsANegation() throws {
        let result = try #require(instrument("let ready = !(flag)", at: "!(flag)", kind: .wrapWithNegation))

        #expect(result.hasPrefix("let ready = \(wrap)(!(flag))"))
    }

    @Test("Given a removed statement, when instrumented, then an activation call takes its place")
    func replacesARemovedStatementWithTheActivationCall() throws {
        let mutated = "let f = {\n    \n    run()\n}"
        let mutant = makeMutantDescriptor(
            filePath: Self.path, utf8Offset: 14, originalText: "setUp()", mutatedText: "",
            replacementKind: .removeStatement, mutatedSourceContent: mutated
        )

        let result = try #require(ActivationInstrumenter(importStyle: .implicit).instrument(mutant))

        #expect(result.hasPrefix("let f = {\n    \(activated)\n    run()\n}"))
    }

    @Test(
        "Given a mutation where a call cannot go, when instrumented, then the mutant is left unmeasured",
        arguments: [
            ("enum Flag: Bool { case on = false }", "false"),
            ("struct S { @Clamped(0 - 1) var x = 0 }", "-"),
            ("let p = #Predicate<Int> { $0 - 1 > 0 }", "-"),
            ("#if false\nlet x = 1\n#endif", "false"),
        ]
    )
    func leavesUnsupportedContextsUnmeasured(source: String, needle: String) {
        #expect(instrument(source, at: needle, kind: needle == "false" ? .booleanLiteral : .binaryOperator) == nil)
    }

    @Test("Given a mutant without mutated content, when instrumented, then nothing is produced")
    func needsMutatedContent() {
        #expect(ActivationInstrumenter(importStyle: .implicit).instrument(makeMutantDescriptor()) == nil)
    }

    @Test("Given a file without Foundation, when instrumented, then an import in the project's style comes first")
    func addsTheImportInTheProjectsStyle() throws {
        let implicit = try #require(instrument("let x = 1 - 1", at: "-"))
        let explicit = try #require(instrument("let x = 1 - 1", at: "-", importStyle: .explicit))
        let imported = try #require(instrument("import Foundation\nlet x = 1 - 1", at: "-"))
        let support = SupportDeclarations.perFile(for: Self.path)

        #expect(implicit.hasSuffix(SupportDeclarations.importLine(.implicit) + "\n\n" + support + "\n"))
        #expect(explicit.hasSuffix(SupportDeclarations.importLine(.explicit) + "\n\n" + support + "\n"))
        #expect(imported.hasSuffix("\n\n" + support + "\n"))
        #expect(!imported.contains("\n\n" + SupportDeclarations.importLine(.implicit)))
    }

    @Test(
        "Given an instrumented file, when parsed, then it has no syntax errors",
        arguments: [
            "struct C {\n    var limit = 10 - 1\n}", "let ok = flag && count - 1 > 2", "let f = { (n: Int) in n - 1 }",
        ]
    )
    func producesValidSyntax(source: String) throws {
        let result = try #require(instrument(source, at: "-"))

        #expect(!Parser.parse(source: result).hasError)
    }

    // MARK: - Helpers

    @Test("Given a file whose operators do not fold elsewhere, when instrumented, then the mutation is still wrapped")
    func aFoldErrorElsewhereDoesNotStopInstrumenting() throws {
        let content = "let limit = 10 - 1\nlet bad = 1 == 2 == 3"

        let result = try #require(instrument(content, at: "-"))

        #expect(result.contains(SupportDeclarations.activatingCall(for: Self.path)))
    }

    private func instrument(
        _ mutated: String,
        at needle: String,
        kind: ReplacementKind = .binaryOperator,
        importStyle: ImportStyle = .implicit
    ) -> String? {
        guard let range = mutated.range(of: needle) else { return nil }
        let offset = mutated.utf8.distance(from: mutated.utf8.startIndex, to: range.lowerBound)
        let mutant = makeMutantDescriptor(
            filePath: Self.path, utf8Offset: offset, mutatedText: needle, replacementKind: kind,
            mutatedSourceContent: mutated
        )
        return ActivationInstrumenter(importStyle: importStyle).instrument(mutant)
    }
}
