import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Source change invalidation")
struct SourceChangeInvalidationTests {

    @Test("Given an edit that leaves offsets alone, when keys are compared, then they differ")
    func editThatPreservesOffsetsChangesTheKey() async throws {
        let project = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(project) }

        let before = try await keys(for: "func f() -> Bool { 1 > 2 }\n", in: project)
        let after = try await keys(for: "func f() -> Bool { 9 > 8 }\n", in: project)

        #expect(!before.isEmpty, "expected the relational operator to be mutated")
        #expect(before.isDisjoint(with: after), "a verdict measured on the old code would be replayed")
    }

    @Test("Given unchanged source, when keys are compared, then they match")
    func unchangedSourceKeepsTheKey() async throws {
        let project = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(project) }

        let source = "func f() -> Bool { 1 > 2 }\n"

        let first = try await keys(for: source, in: project)
        let second = try await keys(for: source, in: project)

        #expect(first == second, "an untouched file must keep its cached verdicts")
    }

    @Test("Given two byte-identical files, when keys are compared, then their mutants do not collide")
    func identicalFilesDoNotShareKeys() async throws {
        let project = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(project) }

        let source = "func f() -> Bool { 1 > 2 }\n"

        let alpha = try await keys(for: source, in: project, named: "Alpha.swift")
        let beta = try await keys(for: source, in: project, named: "Beta.swift")

        #expect(
            alpha.isDisjoint(with: beta),
            "mutants in different files compile into different places and are not interchangeable"
        )
    }

    // MARK: - Private

    private func keys(
        for source: String,
        in project: URL,
        named name: String = "Foo.swift"
    ) async throws -> Set<MutantCacheKey> {
        try FileHelpers.write(source, named: name, in: project)

        let input = try await DiscoveryPipeline().run(
            input: makeDiscoveryInput(projectPath: project.path, sourcesPath: project.path)
        )

        return Set(input.mutants.filter { $0.filePath.hasSuffix(name) }.map(MutantCacheKey.make(for:)))
    }
}
