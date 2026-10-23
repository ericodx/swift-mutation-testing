import Foundation
import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("SchemaNarrower — excluding the mutants of a failing file")
struct SchemaNarrowerExclusionTests {
    @Test("Given the sandbox copy is gone, when its mutants are excluded, then all go and the original is restored")
    func aMissingSandboxCopyExcludesEveryMutantAndRestoresTheOriginal() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let original = dir.appendingPathComponent("Foo.swift")
        let sandboxCopy = dir.appendingPathComponent("sandbox/Foo.swift")
        try FileManager.default.createDirectory(
            at: sandboxCopy.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "let x = true".write(to: original, atomically: true, encoding: .utf8)
        let mutants = [
            makeMutantDescriptor(id: "swift-mutation-testing_0", filePath: original.path, isSchematizable: true)
        ]

        let excluded = try SchemaNarrower.excludeProblematicMutants(
            sandboxPath: sandboxCopy.path,
            originalPath: original.path,
            errorOutput: "\(sandboxCopy.path):1:5: error: cannot find 'y' in scope",
            mutantsInFile: mutants,
            importStyle: .implicit
        )

        #expect(excluded.map(\.id) == ["swift-mutation-testing_0"])
        #expect(try String(contentsOf: sandboxCopy, encoding: .utf8) == "let x = true")
    }

    @Test("Given a sandbox directory that cannot be written, when the original cannot be restored, then it throws")
    func aLinkThatCannotBeRestoredStopsTheNarrowing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let original = dir.appendingPathComponent("Foo.swift")
        let sandbox = dir.appendingPathComponent("sandbox")
        let sandboxCopy = sandbox.appendingPathComponent("Foo.swift")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        try "let x = true".write(to: original, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.path)
            FileHelpers.cleanup(dir)
        }
        let mutants = [
            makeMutantDescriptor(id: "swift-mutation-testing_0", filePath: original.path, isSchematizable: true)
        ]

        #expect(throws: IntegrityError.sourceNotRestored(path: original.path)) {
            try SchemaNarrower.excludeProblematicMutants(
                sandboxPath: sandboxCopy.path,
                originalPath: original.path,
                errorOutput: "\(sandboxCopy.path):1:5: error: cannot find 'y' in scope",
                mutantsInFile: mutants,
                importStyle: .implicit
            )
        }
    }

    @Test("Given an error inside a mutant's case, when its mutants are excluded, then only that one goes")
    func anErrorInsideACaseExcludesOnlyThatMutant() throws {
        let fixture = try SchematizedFixture()
        defer { fixture.cleanUp() }
        let blamed = fixture.indexed[1].mutantID

        let excluded = try fixture.exclude(errorLine: try fixture.lineAfter("case \"\(blamed)\":"))

        #expect(excluded.map(\.id) == [blamed])
        let narrowed = try String(contentsOf: fixture.sandboxCopy, encoding: .utf8)
        #expect(narrowed.hasPrefix(LintSuppression.opening))
        #expect(narrowed.hasSuffix(LintSuppression.closing))
        #expect(!narrowed.contains(blamed))
        #expect(narrowed.contains(fixture.indexed[0].mutantID))
        #expect(narrowed.contains(fixture.indexed[2].mutantID))
    }

    @Test("Given an error in the default branch, when its mutants are excluded, then no case above it is blamed")
    func anErrorInTheDefaultBranchBlamesNoCase() throws {
        let fixture = try SchematizedFixture()
        defer { fixture.cleanUp() }

        let excluded = try fixture.exclude(errorLine: try fixture.lineAfter("default:"))

        #expect(excluded.map(\.id) == fixture.indexed.map(\.mutantID))
        #expect(try String(contentsOf: fixture.sandboxCopy, encoding: .utf8) == SchematizedFixture.original)
    }

    @Test("Given an error on a switch inside a mutant's case, when its mutants are excluded, then only that one goes")
    func anErrorOnANestedSwitchExcludesOnlyThatMutant() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withSwitch)
        defer { fixture.cleanUp() }
        let blamed = fixture.indexed[0].mutantID

        let excluded = try fixture.exclude(errorLine: try fixture.line("switch kind {", after: "case \"\(blamed)\":"))

        #expect(excluded.map(\.id) == [blamed])
    }

    @Test(
        "Given an error below a default inside a mutant's case, when its mutants are excluded, then only that one goes")
    func anErrorBelowANestedDefaultExcludesOnlyThatMutant() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withSwitch)
        defer { fixture.cleanUp() }
        let blamed = fixture.indexed[1].mutantID

        let excluded = try fixture.exclude(errorLine: try fixture.line("default:", after: "case \"\(blamed)\":") + 1)

        #expect(excluded.map(\.id) == [blamed])
    }

    @Test(
        "Given an error under the dispatch's default, when its mutants are excluded, then no nested switch is mistaken for a case"
    )
    func anErrorUnderTheDispatchDefaultWithANestedSwitchBlamesNoCase() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withSwitch)
        defer { fixture.cleanUp() }

        let excluded = try fixture.exclude(errorLine: try fixture.line("switch kind {", after: "default:"))

        #expect(excluded.map(\.id) == fixture.indexed.map(\.mutantID))
    }

    @Test("Given an error after a local function in a mutant's case, when its mutants are excluded, then that one goes")
    func anErrorAfterALocalFunctionsDispatchExcludesTheEnclosingMutant() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withLocalFunction)
        defer { fixture.cleanUp() }
        let blamed = fixture.indexed[1].mutantID

        let excluded = try fixture.exclude(
            errorLine: try fixture.line("return inner(a) + b", after: "case \"\(blamed)\":"))

        #expect(excluded.map(\.id) == [blamed])
    }

    @Test(
        "Given an error in a local function's original body inside a mutant's case, when excluded, then that one goes")
    func anErrorInALocalFunctionsDefaultExcludesTheEnclosingMutant() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withLocalFunction)
        defer { fixture.cleanUp() }
        let blamed = fixture.indexed[1].mutantID

        let excluded = try fixture.exclude(errorLine: try fixture.line("return x + 1", after: "case \"\(blamed)\":"))

        #expect(excluded.map(\.id) == [blamed])
    }

    @Test("Given an error in the local function's mutant case, when excluded, then the local function's mutant goes")
    func anErrorInALocalFunctionsCaseExcludesItsMutant() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withLocalFunction)
        defer { fixture.cleanUp() }
        let blamed = fixture.indexed[0].mutantID

        let excluded = try fixture.exclude(errorLine: try fixture.line("return x - 1", after: "default:"))

        #expect(excluded.map(\.id) == [blamed])
    }

    @Test(
        "Given an error between the dispatch's switch and its first case, when excluded, then no case above it is blamed"
    )
    func anErrorAboveTheFirstCaseBlamesNoEarlierCase() throws {
        let fixture = try SchematizedFixture(source: SchematizedFixture.withLocalFunction)
        defer { fixture.cleanUp() }
        let lines = fixture.schema.components(separatedBy: "\n")
        let dispatches = lines.indices.filter { lines[$0].hasPrefix("switch \(SupportDeclarations.identifierPrefix)") }
        let innerSwitch = try #require(dispatches.dropFirst().first)

        let excluded = try fixture.exclude(errorLine: innerSwitch + 1)

        #expect(excluded.map(\.id) == fixture.indexed.map(\.mutantID))
    }

    // MARK: - Private

    private struct SchematizedFixture {
        static let original = """
            struct Foo {
                func combine(_ a: Int, _ b: Int) -> Int {
                    let first = a + b
                    let second = a - b
                    return first * second
                }
            }
            """

        static let withSwitch = """
            struct Foo {
                func pick(_ kind: Int, _ a: Int, _ b: Int) -> Int {
                    switch kind {
                    case 0:
                        return a + b
                    default:
                        return a - b
                    }
                }
            }
            """

        static let withLocalFunction = """
            struct Foo {
                func outer(_ a: Int, _ b: Int) -> Int {
                    func inner(_ x: Int) -> Int {
                        return x + 1
                    }
                    return inner(a) - b
                }
            }
            """

        let directory: URL
        let originalFile: URL
        let sandboxCopy: URL
        let indexed: [IndexedMutationPoint]
        let schema: String

        init(source: String = Self.original) throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            originalFile = directory.appendingPathComponent("Foo.swift")
            sandboxCopy = directory.appendingPathComponent("sandbox/Foo.swift")
            try FileManager.default.createDirectory(
                at: sandboxCopy.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try source.write(to: originalFile, atomically: true, encoding: .utf8)

            let parsed = ParsedSource(
                file: SourceFile(path: originalFile.path, content: source),
                syntax: Parser.parse(source: source)
            )
            indexed = ArithmeticOperatorReplacement().mutations(in: parsed).enumerated().map {
                IndexedMutationPoint(
                    index: $0.offset, mutation: $0.element, isSchematizable: true,
                    fingerprint: "fingerprint-\($0.offset)"
                )
            }
            let all = indexed.map { $0.toDescriptor(mutatedContent: nil, sourceContentHash: "hash") }
            let generated = try #require(
                SchemaNarrower.regeneratedSchema(originalPath: originalFile.path, keeping: all)
            )
            schema = LintSuppression.wrapping(generated)
            try schema.write(to: sandboxCopy, atomically: true, encoding: .utf8)
        }

        var descriptors: [MutantDescriptor] {
            indexed.map { $0.toDescriptor(mutatedContent: nil, sourceContentHash: "hash") }
        }

        func lineAfter(_ marker: String) throws -> Int {
            let lines = schema.components(separatedBy: "\n")
            let index = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == marker })
            return index + 2
        }

        func line(_ text: String, after marker: String) throws -> Int {
            let lines = schema.components(separatedBy: "\n")
            let start = try #require(lines.firstIndex { $0 == marker })
            let index = try #require(
                lines[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == text && $0 != marker }
            )
            return index + 1
        }

        func exclude(errorLine: Int) throws -> [MutantDescriptor] {
            try SchemaNarrower.excludeProblematicMutants(
                sandboxPath: sandboxCopy.path,
                originalPath: originalFile.path,
                errorOutput: "\(sandboxCopy.path):\(errorLine):5: error: cannot find 'y' in scope",
                mutantsInFile: descriptors,
                importStyle: .implicit
            )
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }
    }
}
