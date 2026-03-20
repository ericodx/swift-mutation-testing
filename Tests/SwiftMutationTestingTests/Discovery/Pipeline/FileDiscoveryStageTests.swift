import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("FileDiscoveryStage")
struct FileDiscoveryStageTests {
    private let stage = FileDiscoveryStage()

    private func makeInput(
        sourcesPath: String,
        excludePatterns: [String] = []
    ) -> DiscoveryInput {
        DiscoveryInput(
            projectPath: sourcesPath,
            sourcesPath: sourcesPath,
            excludePatterns: excludePatterns,
            operators: []
        )
    }

    @Test("Given swift file in directory, when run, then returns it as SourceFile")
    func findsSwiftFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("let x = 1", named: "Foo.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Foo.swift"))
        #expect(result[0].content == "let x = 1")
    }

    @Test("Given non-swift file, when run, then ignores it")
    func ignoresNonSwiftFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("hello", named: "README.md", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.isEmpty)
    }

    @Test("Given file ending with Tests.swift, when run, then excludes it")
    func excludesTestsSuffix() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("class T {}", named: "FooTests.swift", in: dir)
        try FileHelpers.write("class S {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /Tests/ directory, when run, then excludes it")
    func excludesTestsDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("class T {}", named: "Foo.swift", in: testsDir)
        try FileHelpers.write("class S {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /.build/ directory, when run, then excludes it")
    func excludesBuildDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let buildDir = dir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Artifact.swift", in: buildDir)
        try FileHelpers.write("let y = 2", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /.swift-mutation-testing-derived-data/, when run, then excludes it")
    func excludesDerivedDataDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let derivedDir =
            dir
            .appendingPathComponent(".swift-mutation-testing-derived-data")
            .appendingPathComponent("Build")
        try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "GeneratedAssetSymbols.swift", in: derivedDir)
        try FileHelpers.write("let y = 2", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /.xmr-cache/, when run, then excludes it")
    func excludesXmrCacheDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheDir = dir.appendingPathComponent(".xmr-cache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Cached.swift", in: cacheDir)
        try FileHelpers.write("let y = 2", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /DerivedData/, when run, then excludes it")
    func excludesXcodeDerivedData() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let derivedData = dir.appendingPathComponent("DerivedData")
        try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Generated.swift", in: derivedData)
        try FileHelpers.write("let y = 2", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given excludePatterns, when run, then excludes matching files")
    func respectsExcludePatterns() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let generatedDir = dir.appendingPathComponent("Generated")
        try FileManager.default.createDirectory(at: generatedDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Model.swift", in: generatedDir)
        try FileHelpers.write("let y = 2", named: "Source.swift", in: dir)

        let input = makeInput(sourcesPath: dir.path, excludePatterns: ["/Generated/"])
        let result = try stage.run(input: input)

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given non-existent sources path, when run, then throws sourcesPathNotFound")
    func throwsWhenPathNotFound() {
        let input = makeInput(sourcesPath: "/nonexistent/path/that/does/not/exist")
        #expect(throws: FileDiscoveryError.sourcesPathNotFound("/nonexistent/path/that/does/not/exist")) {
            try stage.run(input: input)
        }
    }
}
