import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("ImportStyle")
struct ImportStyleTests {

    @Test("Given imports without access levels, when read, then the style is implicit")
    func bareImportsAreImplicit() {
        #expect(ImportStyle.of(Parser.parse(source: "import Foundation\nimport SwiftSyntax\nfunc f() {}")) == .implicit)
    }

    @Test(
        "Given an import with an access level, when read, then the style is explicit",
        arguments: ["internal import Foundation", "public import Foundation", "private import Darwin"]
    )
    func anImportWithALevelIsExplicit(line: String) {
        #expect(ImportStyle.of(Parser.parse(source: line + "\nfunc f() {}")) == .explicit)
    }

    @Test("Given a file with no import at all, when read, then the style is implicit")
    func noImportIsImplicit() {
        #expect(ImportStyle.of(Parser.parse(source: "func f() {}")) == .implicit)
    }

    @Test("Given several sources, when read together, then one explicit import makes the project explicit")
    func oneExplicitSourceDecidesForAll() {
        let bare = makeParsedSource("import Foundation\nfunc f() {}")
        let explicit = makeParsedSource("internal import Foundation\nfunc g() {}")

        #expect(ImportStyle.of([bare, bare]) == .implicit)
        #expect(ImportStyle.of([bare, explicit]) == .explicit)
    }

    @Test("Given a file, when asked, then it imports Foundation only if an import names it")
    func importingFoundationIsRead() {
        #expect(ImportStyle.importsFoundation(Parser.parse(source: "import Foundation\nfunc f() {}")))
        #expect(ImportStyle.importsFoundation(Parser.parse(source: "public import Foundation\nfunc f() {}")))
        #expect(ImportStyle.importsFoundation(Parser.parse(source: "import Foundation.NSDate\nfunc f() {}")))
        #expect(!ImportStyle.importsFoundation(Parser.parse(source: "import SwiftSyntax\nfunc f() {}")))
    }

    @Test("Given an access-level Foundation import inside an active #if, when read, then it is seen")
    func anImportInsideAnActiveConditionIsSeen() {
        let syntax = Parser.parse(
            source: "#if canImport(Foundation)\ninternal import Foundation\n#endif\nfunc f() {}"
        )

        #expect(ImportStyle.importsFoundation(syntax))
        #expect(ImportStyle.of(syntax) == .explicit)
    }

    @Test("Given an import nested in two active #if blocks, when read, then it is seen")
    func anImportInsideNestedConditionsIsSeen() {
        let syntax = Parser.parse(
            source: "#if canImport(Darwin)\n#if DEBUG\ninternal import Foundation\n#endif\n#endif\nfunc f() {}"
        )

        #expect(ImportStyle.importsFoundation(syntax))
        #expect(ImportStyle.of(syntax) == .explicit)
    }

    @Test("Given a Foundation import only in an inactive #if clause, when read, then it is not seen")
    func anImportInsideAnInactiveClauseIsIgnored() {
        let syntax = Parser.parse(
            source: "#if os(Linux)\ninternal import Foundation\n#else\nimport Darwin\n#endif\nfunc f() {}"
        )

        #expect(!ImportStyle.importsFoundation(syntax))
        #expect(ImportStyle.of(syntax) == .implicit)
    }
}
