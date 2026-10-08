import Foundation
import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("SchemaNarrower — mutants matched by canonical path")
struct SchemaNarrowerPathTests {
    @Test("Given mutants reached through a symlinked project, when one case fails, then only that mutant is excluded")
    func aMutantBehindASymlinkIsBlamed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let (artifact, excluded) = try await fixture.narrow(blaming: [1])

        #expect(artifact != nil)
        #expect(excluded.map(\.id) == [fixture.mutants[1].id])
    }

    @Test("Given errors in two cases listed out of order, when narrowed, then the excluded mutants keep input order")
    func excludedMutantsKeepInputOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let (_, excluded) = try await fixture.narrow(blaming: [2, 0])

        #expect(excluded.map(\.id) == [fixture.mutants[0].id, fixture.mutants[2].id])
    }

    private struct Fixture {
        static let original = """
            struct Foo {
                func combine(_ a: Int, _ b: Int) -> Int {
                    let first = a + b
                    let second = a - b
                    return first * second
                }
            }
            """

        let root: URL
        let real: URL
        let link: URL
        let sandbox: Sandbox
        let mutants: [MutantDescriptor]
        let schema: String

        init() throws {
            root = try FileHelpers.makeTemporaryDirectory()
            real = root.appendingPathComponent("real")
            link = root.appendingPathComponent("link")
            sandbox = Sandbox(rootURL: root.appendingPathComponent("sandbox"))
            let sources = real.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: sandbox.rootURL.appendingPathComponent("Sources"), withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let original = sources.appendingPathComponent("Foo.swift")
            try Self.original.write(to: original, atomically: true, encoding: .utf8)

            let parsed = ParsedSource(
                file: SourceFile(path: original.path, content: Self.original),
                syntax: Parser.parse(source: Self.original)
            )
            let linked = link.appendingPathComponent("Sources/Foo.swift").path
            mutants = ArithmeticOperatorReplacement().mutations(in: parsed).enumerated().map { index, point in
                let descriptor = IndexedMutationPoint(
                    index: index, mutation: point, isSchematizable: true, fingerprint: "f\(index)"
                ).toDescriptor(mutatedContent: nil, sourceContentHash: "hash")
                return MutantDescriptor(
                    id: descriptor.id, filePath: linked, line: descriptor.line, column: descriptor.column,
                    utf8Offset: descriptor.utf8Offset, originalText: descriptor.originalText,
                    mutatedText: descriptor.mutatedText, operatorIdentifier: descriptor.operatorIdentifier,
                    replacementKind: descriptor.replacementKind, description: descriptor.description,
                    isSchematizable: true, mutatedSourceContent: nil, sourceContentHash: "hash",
                    fingerprint: descriptor.fingerprint
                )
            }
            schema = try #require(SchemaNarrower.regeneratedSchema(originalPath: original.path, keeping: mutants))
            try schema.write(
                to: sandbox.rootURL.appendingPathComponent("Sources/Foo.swift"), atomically: true, encoding: .utf8
            )
        }

        func narrow(blaming indices: [Int]) async throws -> (BuildArtifact?, [MutantDescriptor]) {
            let copy = CanonicalPath.make(for: sandbox.rootURL.path) + "/Sources/Foo.swift"
            let lines = schema.components(separatedBy: "\n")
            let output = try indices.map { index in
                let marker = "case \"\(mutants[index].id)\":"
                let line = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == marker })
                return "\(copy):\(line + 2):5: error: cannot find 'y' in scope"
            }.joined(separator: "\n")
            let narrower = SchemaNarrower(
                stage: BuildStage(launcher: MockProcessLauncher(exitCode: 0)),
                reporter: MockProgressReporter(),
                buildTimeout: 10
            )

            return try await narrower.narrow(
                after: output,
                sandbox: sandbox,
                input: makeRunnerInput(projectPath: real.path, projectType: .spm, mutants: mutants),
                start: Date()
            )
        }

        func cleanUp() {
            FileHelpers.cleanup(root)
        }
    }
}
