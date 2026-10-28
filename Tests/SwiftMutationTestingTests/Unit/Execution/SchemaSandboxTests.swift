import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SchemaSandbox")
struct SchemaSandboxTests {
    @Test("Given the schema installed, when a batch is installed, then the files it leaves out link back")
    func installingABatchReplacesTheSchema() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let schema = try await makeSchemaSandbox(
            projectPath: fixture.project.path, installed: [fixture.foo("foo schema"), fixture.bar("bar schema")]
        )
        defer { try? schema.sandbox.cleanup() }

        try await schema.install([fixture.foo("foo batch")])

        #expect(await schema.installed.map(\.originalPath) == [fixture.fooURL.path])
        #expect(try fixture.content(of: "Foo.swift", in: schema) == LintSuppression.wrapping("foo batch"))
        #expect(fixture.isLink("Bar.swift", in: schema))
    }

    @Test("Given the schema installed, when restored, then every file links back and nothing is installed")
    func restoringLinksEveryFileBack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let schema = try await makeSchemaSandbox(
            projectPath: fixture.project.path, installed: [fixture.foo("foo schema"), fixture.bar("bar schema")]
        )
        defer { try? schema.sandbox.cleanup() }

        try await schema.restore()

        #expect(await schema.installed.isEmpty)
        #expect(fixture.isLink("Foo.swift", in: schema))
        #expect(fixture.isLink("Bar.swift", in: schema))
        #expect(try String(contentsOf: fixture.fooURL, encoding: .utf8) == "let foo = 1")
    }

    @Test("Given a restored sandbox, when the schema is installed again, then the copies hold it once more")
    func installingAfterARestoreWritesTheSchemaAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let schema = try await makeSchemaSandbox(projectPath: fixture.project.path, installed: [fixture.foo("schema")])
        defer { try? schema.sandbox.cleanup() }
        try await schema.restore()

        try await schema.install([fixture.foo("schema")])

        #expect(try fixture.content(of: "Foo.swift", in: schema) == LintSuppression.wrapping("schema"))
        #expect(try String(contentsOf: fixture.fooURL, encoding: .utf8) == "let foo = 1")
    }

    // MARK: - Private

    private struct Fixture {
        let directory: URL
        let project: URL
        let fooURL: URL
        let barURL: URL

        init() throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            project = directory.appendingPathComponent("project")
            let sources = project.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            fooURL = sources.appendingPathComponent("Foo.swift")
            barURL = sources.appendingPathComponent("Bar.swift")
            try "let foo = 1".write(to: fooURL, atomically: true, encoding: .utf8)
            try "let bar = 1".write(to: barURL, atomically: true, encoding: .utf8)
        }

        func foo(_ content: String) -> SchematizedFile {
            SchematizedFile(originalPath: fooURL.path, schematizedContent: content)
        }

        func bar(_ content: String) -> SchematizedFile {
            SchematizedFile(originalPath: barURL.path, schematizedContent: content)
        }

        func copy(of name: String, in schema: SchemaSandbox) -> URL {
            schema.sandbox.rootURL.appendingPathComponent("Sources/\(name)")
        }

        func content(of name: String, in schema: SchemaSandbox) throws -> String {
            try String(contentsOf: copy(of: name, in: schema), encoding: .utf8)
        }

        func isLink(_ name: String, in schema: SchemaSandbox) -> Bool {
            (try? copy(of: name, in: schema).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }
    }
}
