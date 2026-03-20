import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("SchemataGenerator")
struct SchemataGeneratorTests {
    private let generator = SchemataGenerator()

    private func mutationsWithIndices(
        _ source: ParsedSource,
        op: any MutationOperator = BooleanLiteralReplacement(),
        startIndex: Int = 0
    ) -> [(index: Int, point: MutationPoint)] {
        op.mutations(in: source).enumerated().map { (index: startIndex + $0.offset, point: $0.element) }
    }

    @Test("Given one mutation, when generated, then produces switch with one case and default")
    func oneMutationProducesSwitchWithOneCaseAndDefault() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(result.contains("switch __swiftMutationTestingID"))
        #expect(result.contains("case \"swift-mutation-testing_0\""))
        #expect(result.contains("default:"))
    }

    @Test("Given mutation, when generated, then mutated text appears in case body")
    func mutatedTextAppearsInCaseBody() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(result.contains("false"))
    }

    @Test("Given mutation, when generated, then original text appears in default body")
    func originalTextAppearsInDefaultBody() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(result.contains("true"))
    }

    @Test("Given two mutations in same function, when generated, then produces switch with two cases")
    func twoMutationsInSameFunctionProduceTwoCases() {
        let source = makeParsedSource("func f() { let a = true; let b = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(result.contains("case \"swift-mutation-testing_0\""))
        #expect(result.contains("case \"swift-mutation-testing_1\""))
    }

    @Test("Given mutations in two functions, when generated, then each function gets its own switch")
    func mutationsInTwoFunctionsEachGetOwnSwitch() {
        let source = makeParsedSource("func f() { let x = true } func g() { let y = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        let switchCount = result.components(separatedBy: "switch __swiftMutationTestingID").count - 1
        #expect(switchCount == 2)
    }

    @Test("Given generated content, when checked, then does not declare __swiftMutationTestingID")
    func schematizedContentDoesNotDeclareIDVariable() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(!result.contains("var __swiftMutationTestingID"))
    }

    @Test("Given no mutations in function, when generated, then returns original content unchanged")
    func emptyMutationsReturnsOriginalContent() {
        let source = makeParsedSource("func f() { let x = 1 }")
        let result = generator.generate(source: source, mutations: [])
        #expect(result == source.file.content)
    }

    @Test("Given mutation uses correct mutant ID format, when generated, then ID matches swift-mutation-testing prefix")
    func mutantIDUsesCorrectFormat() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source, startIndex: 5)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(result.contains("swift-mutation-testing_5"))
    }

    @Test("Given generated content, when parsed by SwiftSyntax, then has no syntax errors")
    func generatedContentIsParseableBySwiftSyntax() {
        let source = makeParsedSource("func f() { let x = true; let y = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        #expect(!Parser.parse(source: result).hasError)
    }
}
