import Testing

@testable import SwiftMutationTesting

@Suite("LintSuppression")
struct LintSuppressionTests {
    @Test("Given source, when wrapped, then SwiftLint is disabled on the first line and enabled on the last")
    func wrappingDisablesThenEnablesSwiftLint() {
        let lines = LintSuppression.wrapping("let x = 1\n").components(separatedBy: "\n")

        #expect(lines.first == "// swiftlint:disable all")
        #expect(lines.dropLast().last == "// swiftlint:enable all")
        #expect(lines.last == "")
    }

    @Test(
        "Given source, when wrapped and unwrapped, then it comes back unchanged",
        arguments: ["let x = 1", "let x = 1\n", "", "\n\n"]
    )
    func unwrappingRestoresTheSource(source: String) {
        #expect(LintSuppression.unwrapping(LintSuppression.wrapping(source)) == source)
    }

    @Test(
        "Given source that was never wrapped, when unwrapped, then it is left alone",
        arguments: ["let x = 1", "// swiftlint:disable all\nlet x = 1", "let x = 1\n// swiftlint:enable all\n"]
    )
    func unwrappingLeavesUnwrappedSourceAlone(source: String) {
        #expect(LintSuppression.unwrapping(source) == source)
    }
}
