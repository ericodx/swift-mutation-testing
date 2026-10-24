import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SchemaInstaller")
struct SchemaInstallerTests {
    @Test("Given a batch's files, when installed, then each sandbox copy holds its schema wrapped for SwiftLint")
    func installedFilesHoldTheirSchema() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.installer.install(
            [SchematizedFile(originalPath: fixture.foo.path, schematizedContent: "foo schema")], replacing: []
        )

        let installed = try String(contentsOf: fixture.sandboxCopy(of: fixture.foo), encoding: .utf8)
        #expect(installed == LintSuppression.wrapping("foo schema"))
    }

    @Test("Given a file the next batch leaves out, when installed, then its sandbox copy links to the original again")
    func aFileLeftOutIsLinkedBack() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let previous = [
            SchematizedFile(originalPath: fixture.foo.path, schematizedContent: "foo schema"),
            SchematizedFile(originalPath: fixture.bar.path, schematizedContent: "bar schema"),
        ]
        try fixture.installer.install(previous, replacing: [])

        try fixture.installer.install(
            [SchematizedFile(originalPath: fixture.foo.path, schematizedContent: "foo batch 2")], replacing: previous
        )

        let link = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.sandboxCopy(of: fixture.bar).path)
        #expect(URL(fileURLWithPath: link).resolvingSymlinksInPath().path == fixture.canonical(fixture.bar))
        #expect(
            try String(contentsOf: fixture.sandboxCopy(of: fixture.foo), encoding: .utf8)
                == LintSuppression.wrapping("foo batch 2")
        )
    }

    @Test("Given a file outside the project, when installed, then it throws that the schema was not applied")
    func aFileOutsideTheProjectThrows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(throws: IntegrityError.self) {
            try fixture.installer.install(
                [SchematizedFile(originalPath: "/tmp/Elsewhere.swift", schematizedContent: "schema")], replacing: []
            )
        }
    }

    // MARK: - Private

    private struct Fixture {
        let directory: URL
        let project: URL
        let foo: URL
        let bar: URL
        let sandbox: Sandbox

        init() throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            project = directory.appendingPathComponent("project")
            let sources = project.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            foo = sources.appendingPathComponent("Foo.swift")
            bar = sources.appendingPathComponent("Bar.swift")
            try "let foo = 1".write(to: foo, atomically: true, encoding: .utf8)
            try "let bar = 1".write(to: bar, atomically: true, encoding: .utf8)

            let root = directory.appendingPathComponent("sandbox")
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true
            )
            for file in [foo, bar] {
                try FileManager.default.createSymbolicLink(
                    at: root.appendingPathComponent("Sources/\(file.lastPathComponent)"), withDestinationURL: file
                )
            }
            sandbox = Sandbox(rootURL: root)
        }

        var installer: SchemaInstaller {
            SchemaInstaller(sandbox: sandbox, projectPath: project.path)
        }

        func canonical(_ file: URL) -> String {
            file.resolvingSymlinksInPath().path
        }

        func sandboxCopy(of file: URL) -> URL {
            let projectRoot = project.resolvingSymlinksInPath().path
            return URL(fileURLWithPath: sandbox.rootURL.path + canonical(file).dropFirst(projectRoot.count))
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }
    }
}
