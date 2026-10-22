import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("SchemataGenerator")
struct SchemataGeneratorTests {
    private let generator = SchemataGenerator()

    @Test("Given one mutation, when generated, then produces switch with one case and default")
    func oneMutationProducesSwitchWithOneCaseAndDefault() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result.contains("switch __swiftMutationTestingID"))
        #expect(result.contains("case \"swift-mutation-testing_0\""))
        #expect(result.contains("default:"))
    }

    @Test("Given mutation, when generated, then mutated text appears in case body")
    func mutatedTextAppearsInCaseBody() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result.contains("false"))
    }

    @Test("Given mutation, when generated, then original text appears in default body")
    func originalTextAppearsInDefaultBody() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result.contains("true"))
    }

    @Test("Given two mutations in same function, when generated, then produces switch with two cases")
    func twoMutationsInSameFunctionProduceTwoCases() {
        let source = makeParsedSource("func f() { let a = true; let b = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result.contains("case \"swift-mutation-testing_0\""))
        #expect(result.contains("case \"swift-mutation-testing_1\""))
    }

    @Test("Given mutations in two functions, when generated, then each function gets its own switch")
    func mutationsInTwoFunctionsEachGetOwnSwitch() {
        let source = makeParsedSource("func f() { let x = true } func g() { let y = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        let switchCount = result.components(separatedBy: "switch __swiftMutationTestingID").count - 1
        #expect(switchCount == 2)
    }

    @Test("Given an initializer whose body is one call to another, when generated, then the call is not wrapped")
    func aDelegatingInitializerIsNotWrappedInATuple() {
        let source = makeParsedSource("struct S { init() {}; init(c: Bool) { self.init(); print(true) } }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content

        #expect(!result.contains(").1"))
        #expect(result.contains("let _ = \(SupportDeclarations.activationCall(for: source.file.path))\n"))
    }

    @Test("Given a body that is one switch statement with returns, when generated, then nothing is returned from it")
    func aSwitchStatementBodyIsNotReturned() {
        let source = makeParsedSource(
            "func f(_ n: Int) -> Bool { switch n { case 0: return true\ndefault: return false } }"
        )
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content

        #expect(!result.contains("return \n"))
        #expect(!result.contains("return switch"))
        #expect(result.contains("let _ = \(SupportDeclarations.activationCall(for: source.file.path))\n"))
    }

    @Test("Given a nested function with mutations in both bodies, when generated, then both keep their cases")
    func nestedFunctionKeepsItsCasesInsideTheEnclosingOnes() {
        let source = makeParsedSource("func f() -> Bool { func g() -> Bool { return true }; return g() && false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)

        #expect(result.discarded.isEmpty)
        for entry in mutations {
            #expect(result.content.contains("case \"swift-mutation-testing_\(entry.index)\":"))
        }
        let switches = result.content.components(separatedBy: "switch __swiftMutationTestingID").count - 1
        let innerCases = result.content.components(separatedBy: "case \"swift-mutation-testing_0\":").count - 1
        #expect(switches == 3, "the inner switch is copied into the outer case and the outer default")
        #expect(innerCases == 2)
    }

    @Test(
        "Given a one-expression body ending in a comment, when generated, then every case is closed outside it",
        arguments: [
            "func f() -> Bool {\n    true // why\n}\n",
            "func f() -> Bool { true /* why */ }\n",
            "func f() -> Bool {\n    true && false /// doc\n}\nfunc g() -> Bool { false }\n",
        ]
    )
    func aTrailingCommentDoesNotSwallowTheCase(code: String) {
        let source = makeParsedSource(code)
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)

        #expect(!mutations.isEmpty)
        #expect(result.discarded.isEmpty)
        for entry in mutations {
            #expect(result.content.contains("case \"swift-mutation-testing_\(entry.index)\":"))
        }
        #expect(!Parser.parse(source: result.content).hasError)
    }

    @Test("Given a mutation after a nested function, when generated, then it is applied at its own place")
    func mutationAfterANestedFunctionLandsOnItsOwnText() {
        let source = makeParsedSource("func f() -> Bool { func g() -> Bool { return true }; return g() && false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)
        let outerCases = result.content.components(separatedBy: "default:").dropLast().joined()

        #expect(outerCases.contains("g() || false") || outerCases.contains("g() && true"))
        #expect(!result.content.contains("return true || false"))
    }

    @Test("Given three nested functions with mutations in every body, when generated, then each body keeps its cases")
    func threeNestedFunctionsKeepEveryCase() {
        let source = makeParsedSource(
            """
            func f() -> Bool {
                func g() -> Bool {
                    func h() -> Bool { return true }
                    return h() && true
                }
                return g() && true
            }
            """
        )
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)

        #expect(mutations.count == 3)
        #expect(result.discarded.isEmpty)
        for entry in mutations {
            #expect(result.content.contains("case \"swift-mutation-testing_\(entry.index)\":"))
        }
        #expect(!Parser.parse(source: result.content).hasError)
    }

    @Test("Given three nested functions and a function after them, when generated, then the file still parses")
    func threeNestedFunctionsLeaveTheNextFunctionOutside() {
        let source = makeParsedSource(
            """
            func f() -> Bool {
                func g() -> Bool {
                    func h() -> Bool { return true }
                    return h() && true
                }
                return g() && true
            }

            func after() -> Bool { let a = true; let b = true; return a && b }
            """
        )
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)

        #expect(mutations.count == 5)
        #expect(result.discarded.isEmpty)
        for entry in mutations {
            #expect(result.content.contains("case \"swift-mutation-testing_\(entry.index)\":"))
        }
        #expect(!Parser.parse(source: result.content).hasError)
    }

    @Test("Given generated content, when checked, then it ends with its own ID variable, named after the file")
    func schematizedContentDeclaresItsOwnIDVariable() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result.hasSuffix("\n\n" + SupportDeclarations.perFile(for: source.file.path) + "\n"))
        #expect(result.components(separatedBy: "internal var __swiftMutationTestingID_").count == 2)
        #expect(result.contains("switch \(SupportDeclarations.identifier(for: source.file.path)) {"))
    }

    @Test("Given a file without a Foundation import, when generated, then one is added in the project's style")
    func theImportFollowsTheProjectStyle() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let block = SupportDeclarations.perFile(for: source.file.path)

        let implicit = generator.generate(source: source, mutations: mutations, importStyle: .implicit).content
        let explicit = generator.generate(source: source, mutations: mutations, importStyle: .explicit).content

        #expect(implicit.hasSuffix("\n\nimport Foundation\n\n" + block + "\n"))
        #expect(explicit.hasSuffix("\n\ninternal import Foundation\n\n" + block + "\n"))
    }

    @Test("Given a file that already imports Foundation, when generated, then no import is added")
    func anExistingFoundationImportIsEnough() {
        let source = makeParsedSource("internal import Foundation\nfunc f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations, importStyle: .explicit).content

        #expect(result.hasSuffix("\n\n" + SupportDeclarations.perFile(for: source.file.path) + "\n"))
        #expect(result.components(separatedBy: "import Foundation").count == 2)
    }

    @Test("Given a body of statements, when generated, then every case records its activation before them")
    func everyCaseRecordsItsActivationFirst() {
        let source = makeParsedSource("func f() { let x = true }\nfunc g() { let y = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        let lines = result.components(separatedBy: "\n")
        let caseLines = lines.indices.filter { lines[$0].hasPrefix("case \"swift-mutation-testing_") }

        #expect(caseLines.count == 2)
        let activation = SupportDeclarations.activationCall(for: source.file.path)
        #expect(caseLines.allSatisfy { lines[$0 + 1] == "let _ = " + activation })
        #expect(!result.contains("default:\nlet _ ="))
    }

    @Test("Given a body that is one expression, when generated, then the case stays one expression")
    func anExpressionBodyStaysAnExpression() {
        let source = makeParsedSource("func add(_ a: Int, _ b: Int) -> Int { a + b }")
        let mutations = ArithmeticOperatorReplacement().mutations(in: source).enumerated().map {
            (index: $0.offset, point: $0.element)
        }
        let result = generator.generate(source: source, mutations: mutations).content

        let activation = SupportDeclarations.activationCall(for: source.file.path)
        #expect(result.contains("case \"swift-mutation-testing_0\":\n(\(activation), a - b \n).1\n"))
        #expect(result.contains("default:\na + b \n"))
        #expect(!result.contains("let _ ="))
    }

    @Test("Given a mutation that empties a one-expression body, when generated, then the case only records activation")
    func anEmptiedExpressionBodyLeavesOnlyTheActivation() {
        let source = makeParsedSource("func f() { store() }")
        let real = ArithmeticOperatorReplacement().mutations(in: makeParsedSource("func f() { a + b }"))[0]
        let removal = MutationPoint(
            operatorIdentifier: "RemoveSideEffects", filePath: real.filePath, line: 1, column: 12,
            utf8Offset: 11, originalText: "store()", mutatedText: "", replacement: real.replacement,
            description: "remove store()"
        )
        let result = generator.generate(source: source, mutations: [(index: 0, point: removal)]).content

        let activation = SupportDeclarations.activationCall(for: source.file.path)
        #expect(result.contains("case \"swift-mutation-testing_0\":\nlet _ = \(activation)\n \n"))
        #expect(!result.contains(").1"))
    }

    @Test("Given a value-returning body that is one if expression, when generated, then every branch returns it")
    func aConditionalReturningBodyReturnsInEveryBranch() {
        let source = makeParsedSource("func f(_ c: Bool) -> Int { if c { 1 } else { 2 } }")
        let mutations = NegateConditional().mutations(in: source).enumerated().map {
            (index: $0.offset, point: $0.element)
        }
        let result = generator.generate(source: source, mutations: mutations).content

        let activation = SupportDeclarations.activationCall(for: source.file.path)
        #expect(result.contains("let _ = \(activation)\nreturn if !(c) { 1 } else { 2 } \n"))
        #expect(result.contains("default:\nreturn if c { 1 } else { 2 } \n"))
    }

    @Test("Given a body that is one if statement returning nothing, when generated, then no branch returns")
    func aConditionalVoidBodyDoesNotReturn() {
        let source = makeParsedSource("func f(_ c: Bool) { if c { print(1) } }")
        let mutations = NegateConditional().mutations(in: source).enumerated().map {
            (index: $0.offset, point: $0.element)
        }
        let result = generator.generate(source: source, mutations: mutations).content

        let schema = result.components(separatedBy: SupportDeclarations.perFile(for: source.file.path))[0]
        let activation = SupportDeclarations.activationCall(for: source.file.path)
        #expect(schema.contains("let _ = \(activation)\nif !(c) { print(1) } \n"))
        #expect(!schema.contains("return"))
    }

    @Test("Given a mutation outside every function body, when generated, then it is returned as discarded")
    func aMutationOutsideAnyBodyIsDiscarded() {
        let source = makeParsedSource("let flag = true\nfunc f() { let x = true }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations)

        #expect(mutations.count == 2)
        #expect(result.discarded.map(\.line) == [1])
        #expect(result.content.contains("case \"swift-mutation-testing_1\":"))
        #expect(!result.content.contains("case \"swift-mutation-testing_0\":"))
    }

    @Test("Given every mutation placed, when generated, then nothing is discarded")
    func placedMutationsAreNotDiscarded() {
        let source = makeParsedSource("func f() { let x = true }")
        let result = generator.generate(source: source, mutations: mutationsWithIndices(source))

        #expect(result.discarded.isEmpty)
    }

    @Test("Given no mutations in function, when generated, then returns original content unchanged")
    func emptyMutationsReturnsOriginalContent() {
        let source = makeParsedSource("func f() { let x = 1 }")
        let result = generator.generate(source: source, mutations: []).content
        #expect(result == source.file.content)
    }

    @Test("Given mutation uses correct mutant ID format, when generated, then ID matches swift-mutation-testing prefix")
    func mutantIDUsesCorrectFormat() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = mutationsWithIndices(source, startIndex: 5)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result.contains("swift-mutation-testing_5"))
    }

    @Test("Given mutation at file scope, when generated, then returns original content unchanged")
    func mutationAtFileScopeIsSkipped() {
        let source = makeParsedSource("let x = true")
        let mutations = mutationsWithIndices(source)
        #expect(!mutations.isEmpty)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(result == source.file.content)
    }

    @Test("Given generated content, when parsed by SwiftSyntax, then has no syntax errors")
    func generatedContentIsParseableBySwiftSyntax() {
        let source = makeParsedSource("func f() { let x = true; let y = false }")
        let mutations = mutationsWithIndices(source)
        let result = generator.generate(source: source, mutations: mutations).content
        #expect(!Parser.parse(source: result).hasError)
    }
}
