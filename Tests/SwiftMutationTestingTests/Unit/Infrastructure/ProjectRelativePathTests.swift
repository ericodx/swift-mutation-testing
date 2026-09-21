import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProjectRelativePath")
struct ProjectRelativePathTests {

    @Test("Given a path inside the project, when relativized, then the root is stripped")
    func stripsProjectRoot() {
        let result = ProjectRelativePath.make(for: "/work/app/Tests/FooTests.swift", in: "/work/app")

        #expect(result == "Tests/FooTests.swift")
    }

    @Test("Given a project path with a trailing slash, when relativized, then the result is unchanged")
    func handlesTrailingSlashInProjectPath() {
        let result = ProjectRelativePath.make(for: "/work/app/Tests/FooTests.swift", in: "/work/app/")

        #expect(result == "Tests/FooTests.swift")
    }

    @Test("Given a path outside the project, when relativized, then it is returned unchanged")
    func leavesOutsidePathsAlone() {
        let result = ProjectRelativePath.make(for: "/elsewhere/FooTests.swift", in: "/work/app")

        #expect(result == "/elsewhere/FooTests.swift")
    }

    @Test("Given a sibling directory sharing the project's prefix, then it is not treated as inside")
    func doesNotMatchPartialDirectoryName() {
        let result = ProjectRelativePath.make(for: "/work/application/FooTests.swift", in: "/work/app")

        #expect(result == "/work/application/FooTests.swift")
    }

    @Test("Given a symlinked path, when relativized, then it resolves to the real location")
    func resolvesSymlinks() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let real = dir.appendingPathComponent("FooTests.swift")
        try "import XCTest".write(to: real, atomically: true, encoding: .utf8)

        let link = dir.appendingPathComponent("LinkedTests.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let result = ProjectRelativePath.make(for: link.path, in: dir.path)

        #expect(result == "FooTests.swift")
    }
}
