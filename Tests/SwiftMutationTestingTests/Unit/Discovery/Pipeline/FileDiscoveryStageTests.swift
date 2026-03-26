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
            scheme: "Scheme",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 4,
            noCache: false,
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

    @Test("Given file inside /.swift-mutation-testing-cache/, when run, then excludes it")
    func excludesCacheDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheDir = dir.appendingPathComponent(".swift-mutation-testing-cache")
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

    @Test("Given file ending with Mock.swift, when run, then excludes it")
    func excludesMockSuffix() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("class M {}", named: "UserMock.swift", in: dir)
        try FileHelpers.write("class S {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file ending with Spec.swift, when run, then excludes it")
    func excludesSpecSuffix() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("class S {}", named: "UserSpec.swift", in: dir)
        try FileHelpers.write("class P {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /Mocks/ directory, when run, then excludes it")
    func excludesMocksDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let mocksDir = dir.appendingPathComponent("Mocks")
        try FileManager.default.createDirectory(at: mocksDir, withIntermediateDirectories: true)
        try FileHelpers.write("class M {}", named: "UserMock.swift", in: mocksDir)
        try FileHelpers.write("class S {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /Stubs/ directory, when run, then excludes it")
    func excludesStubsDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let stubsDir = dir.appendingPathComponent("Stubs")
        try FileManager.default.createDirectory(at: stubsDir, withIntermediateDirectories: true)
        try FileHelpers.write("class S {}", named: "NetworkStub.swift", in: stubsDir)
        try FileHelpers.write("class P {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /Fakes/ directory, when run, then excludes it")
    func excludesFakesDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fakesDir = dir.appendingPathComponent("Fakes")
        try FileManager.default.createDirectory(at: fakesDir, withIntermediateDirectories: true)
        try FileHelpers.write("class F {}", named: "ServiceFake.swift", in: fakesDir)
        try FileHelpers.write("class P {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /TestHelpers/ directory, when run, then excludes it")
    func excludesTestHelpersDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let helpersDir = dir.appendingPathComponent("TestHelpers")
        try FileManager.default.createDirectory(at: helpersDir, withIntermediateDirectories: true)
        try FileHelpers.write("class H {}", named: "Helper.swift", in: helpersDir)
        try FileHelpers.write("class P {}", named: "Source.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Source.swift"))
    }

    @Test("Given file inside /TestSupport/ directory, when run, then excludes it")
    func excludesTestSupportDirectory() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let supportDir = dir.appendingPathComponent("TestSupport")
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try FileHelpers.write("class H {}", named: "Support.swift", in: supportDir)
        try FileHelpers.write("class P {}", named: "Source.swift", in: dir)

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

    @Test("Given swift file with invalid UTF-8 content, when run, then file is skipped")
    func skipsFileWithInvalidUTF8() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let invalidFile = dir.appendingPathComponent("Invalid.swift")
        let invalidBytes: [UInt8] = [0xFF, 0xFE, 0x00]
        try Data(invalidBytes).write(to: invalidFile)
        try FileHelpers.write("let x = 1", named: "Valid.swift", in: dir)

        let result = try stage.run(input: makeInput(sourcesPath: dir.path))

        #expect(result.count == 1)
        #expect(result[0].path.hasSuffix("Valid.swift"))
    }

    @Test("Given non-existent sources path, when run, then throws sourcesPathNotFound")
    func throwsWhenPathNotFound() {
        let input = makeInput(sourcesPath: "/nonexistent/path/that/does/not/exist")
        #expect(throws: FileDiscoveryError.sourcesPathNotFound("/nonexistent/path/that/does/not/exist")) {
            try stage.run(input: input)
        }
    }
}
