import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("KillerTestFileResolver")
struct KillerTestFileResolverTests {
    @Test("Given XCTest class name, when resolved, then returns file matching class name")
    func resolvesXCTestClassName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        let result = resolver.resolve(testName: "CalculatorTests.testAddition")

        #expect(result == "Tests/CalculatorTests.swift")
    }

    @Test("Given XCTest three-part name, when resolved, then returns file matching middle component")
    func resolvesXCTestThreePartName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        let result = resolver.resolve(testName: "MyModule.CalculatorTests.testAddition")

        #expect(result == "Tests/CalculatorTests.swift")
    }

    @Test("Given Swift Testing function name, when resolved, then returns file containing function")
    func resolvesSwiftTestingFunctionName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("MathTests.swift").path
        try "func testAddition() { }".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        let result = resolver.resolve(testName: "MyModule/MathTests/testAddition")

        #expect(result == "Tests/MathTests.swift")
    }

    @Test("Given a test file outside the project, when resolved, then the path is returned unchanged")
    func returnsPathOutsideProjectUnchanged() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let filePath = dir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: "/somewhere/else")

        let result = resolver.resolve(testName: "CalculatorTests.testAddition")

        #expect(result == filePath)
    }

    @Test("Given unknown test name, when resolved, then returns nil")
    func returnsNilForUnknownTestName() {
        let resolver = KillerTestFileResolver(testFilePaths: ["/some/path/FooTests.swift"], projectPath: "/some")

        let result = resolver.resolve(testName: "UnknownTests.testSomething")

        #expect(result == nil)
    }

    @Test("Given empty test file paths, when resolved, then returns nil")
    func returnsNilWhenNoTestFiles() {
        let resolver = KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")

        let result = resolver.resolve(testName: "SomeTests.testMethod")

        #expect(result == nil)
    }

    @Test("Given a resolved killer file, when hashed by TestFilesHasher, then both agree on the form")
    func resolvedPathMatchesHasherKeys() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try "import XCTest".write(
            toFile: testsDir.appendingPathComponent("CalculatorTests.swift").path,
            atomically: true,
            encoding: .utf8
        )

        let hasher = TestFilesHasher()
        let resolver = KillerTestFileResolver(
            testFilePaths: hasher.testFilePaths(projectPath: dir.path),
            projectPath: dir.path
        )

        let killerFile = try #require(resolver.resolve(testName: "CalculatorTests.testAddition"))
        let hashedKeys = Set(hasher.hashPerFile(projectPath: dir.path).keys)

        #expect(hashedKeys.contains(killerFile), "\(killerFile) is not among \(hashedKeys)")
    }
}
