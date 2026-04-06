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

        let resolver = KillerTestFileResolver(testFilePaths: [filePath])

        let result = resolver.resolve(testName: "CalculatorTests.testAddition")

        #expect(result == filePath)
    }

    @Test("Given XCTest three-part name, when resolved, then returns file matching middle component")
    func resolvesXCTestThreePartName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath])

        let result = resolver.resolve(testName: "MyModule.CalculatorTests.testAddition")

        #expect(result == filePath)
    }

    @Test("Given Swift Testing function name, when resolved, then returns file containing function")
    func resolvesSwiftTestingFunctionName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("MathTests.swift").path
        try "func testAddition() { }".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath])

        let result = resolver.resolve(testName: "MyModule/MathTests/testAddition")

        #expect(result == filePath)
    }

    @Test("Given unknown test name, when resolved, then returns nil")
    func returnsNilForUnknownTestName() {
        let resolver = KillerTestFileResolver(testFilePaths: ["/some/path/FooTests.swift"])

        let result = resolver.resolve(testName: "UnknownTests.testSomething")

        #expect(result == nil)
    }

    @Test("Given empty test file paths, when resolved, then returns nil")
    func returnsNilWhenNoTestFiles() {
        let resolver = KillerTestFileResolver(testFilePaths: [])

        let result = resolver.resolve(testName: "SomeTests.testMethod")

        #expect(result == nil)
    }
}
