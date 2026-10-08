import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("ApplicationVerifier")
struct ApplicationVerifierTests {
    private let verifier = ApplicationVerifier()

    @Test("Given every mutant in the sandbox, when verified, then nothing is thrown")
    func appliedMutantsPass() throws {
        let project = try Project { schema(cases: ["m0", "m1"], for: $0) }
        defer { project.cleanup() }

        try verifier.verify(
            schematizedFiles: [project.file],
            mutants: [
                project.mutant(id: "m0"), project.mutant(id: "m1"),
                project.mutant(id: "m2", schematizable: false, content: "let x = false"),
            ],
            sandbox: project.sandbox, projectPath: project.root.path
        )
    }

    @Test("Given a sandbox copy identical to the original, when verified, then the schema was not applied")
    func identicalCopyIsNotApplied() throws {
        let project = try Project { _ in Project.original }
        defer { project.cleanup() }

        #expect(throws: IntegrityError.schemaNotApplied(path: project.file.originalPath)) {
            try verifier.verify(
                schematizedFiles: [project.file], mutants: [], sandbox: project.sandbox, projectPath: project.root.path
            )
        }
    }

    @Test("Given no sandbox copy of a schematized file, when verified, then the schema was not applied")
    func missingCopyIsNotApplied() throws {
        let project = try Project(schematized: nil)
        defer { project.cleanup() }

        #expect(throws: IntegrityError.schemaNotApplied(path: project.file.originalPath)) {
            try verifier.verify(
                schematizedFiles: [project.file], mutants: [], sandbox: project.sandbox, projectPath: project.root.path
            )
        }
    }

    @Test("Given a schematized file outside the project, when verified, then the schema was not applied")
    func fileOutsideTheProjectIsNotApplied() throws {
        let project = try Project { schema(cases: [], for: $0) }
        defer { project.cleanup() }
        let outside = SchematizedFile(originalPath: "/elsewhere/Foo.swift", schematizedContent: "let x = false")

        #expect(throws: IntegrityError.schemaNotApplied(path: "/elsewhere/Foo.swift")) {
            try verifier.verify(
                schematizedFiles: [outside], mutants: [], sandbox: project.sandbox, projectPath: project.root.path
            )
        }
    }

    @Test("Given a copy without the support declarations, when verified, then the support is missing")
    func copyWithoutSupportIsMissingIt() throws {
        let project = try Project { _ in "switch __swiftMutationTestingID_x {\ncase \"m0\":\nlet x = false\n}" }
        defer { project.cleanup() }

        #expect(throws: IntegrityError.supportMissing(path: project.file.originalPath)) {
            try verifier.verify(
                schematizedFiles: [project.file], mutants: [], sandbox: project.sandbox, projectPath: project.root.path
            )
        }
    }

    @Test("Given schematizable mutants without a case, when verified, then they are named in order")
    func mutantsWithoutACaseAreNotApplied() throws {
        let project = try Project { schema(cases: ["m1"], for: $0) }
        defer { project.cleanup() }

        #expect(throws: IntegrityError.mutantsNotApplied(mutants: ["m0 (Foo.swift:1)", "m2 (Bar.swift:1)"])) {
            try verifier.verify(
                schematizedFiles: [project.file],
                mutants: [
                    project.mutant(id: "m0"), project.mutant(id: "m1"),
                    makeMutantDescriptor(
                        id: "m2", filePath: project.root.appendingPathComponent("Bar.swift").path, isSchematizable: true
                    ),
                ],
                sandbox: project.sandbox, projectPath: project.root.path
            )
        }
    }

    @Test(
        "Given an incompatible mutant with no content or the original's, when verified, then it is not applied",
        arguments: [nil, Project.original]
    )
    func incompatibleMutantWithoutAChangeIsNotApplied(content: String?) throws {
        let project = try Project { schema(cases: [], for: $0) }
        defer { project.cleanup() }

        #expect(throws: IntegrityError.mutantsNotApplied(mutants: ["m9 (Foo.swift:1)"])) {
            try verifier.verify(
                schematizedFiles: [project.file],
                mutants: [project.mutant(id: "m9", schematizable: false, content: content)],
                sandbox: project.sandbox, projectPath: project.root.path
            )
        }
    }

    @Test("Given many mutants of one file, when verified, then the file's original is read once")
    func eachOriginalIsReadOnce() throws {
        let project = try Project { schema(cases: ["m0", "m1", "m2"], for: $0) }
        defer { project.cleanup() }
        let reads = Mutex<[String]>([])
        var counting = ApplicationVerifier()
        counting.read = { path in
            reads.withLock { $0.append(path) }
            return try? String(contentsOfFile: path, encoding: .utf8)
        }

        try counting.verify(
            schematizedFiles: [project.file],
            mutants: [project.mutant(id: "m0"), project.mutant(id: "m1"), project.mutant(id: "m2")]
                + (3 ..< 8).map { project.mutant(id: "m\($0)", schematizable: false, content: "let x = \($0)") },
            sandbox: project.sandbox, projectPath: project.root.path
        )

        let original = project.file.originalPath
        #expect(reads.withLock { $0 }.filter { $0 == original }.count == 2, "once for the schema, once for the rest")
    }

    // MARK: - Helpers

    private func schema(cases: [String], for path: String) -> String {
        let activation = SupportDeclarations.activationCall(for: path)
        let body = cases.map { "case \"\($0)\":\nlet _ = \(activation)\nlet x = false" }
        return "switch \(SupportDeclarations.identifier(for: path)) {\n" + body.joined(separator: "\n")
            + "\ndefault:\nlet x = true\n}\n\n" + SupportDeclarations.perFile(for: path) + "\n"
    }

    private struct Project {
        static let original = "let x = true"

        let root: URL
        let sandbox: Sandbox
        let file: SchematizedFile

        init(schematized: ((String) -> String)? = nil) throws {
            root = try FileHelpers.makeTemporaryDirectory()
            sandbox = Sandbox(rootURL: try FileHelpers.makeTemporaryDirectory())
            let sources = root.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try Self.original.write(to: sources.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
            let path = sources.appendingPathComponent("Foo.swift").path
            let schematized = schematized?(path)
            file = SchematizedFile(originalPath: path, schematizedContent: schematized ?? "")
            if let schematized {
                let copy = sandbox.rootURL.appendingPathComponent("Sources/Foo.swift")
                try FileManager.default.createDirectory(
                    at: copy.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try schematized.write(to: copy, atomically: true, encoding: .utf8)
            }
        }

        func mutant(id: String, schematizable: Bool = true, content: String? = nil) -> MutantDescriptor {
            makeMutantDescriptor(
                id: id, filePath: file.originalPath, isSchematizable: schematizable, mutatedSourceContent: content
            )
        }

        func cleanup() {
            FileHelpers.cleanup(root)
            FileHelpers.cleanup(sandbox.rootURL)
        }
    }
}
