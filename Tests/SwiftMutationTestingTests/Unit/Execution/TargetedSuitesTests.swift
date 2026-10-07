import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TargetedSuites")
struct TargetedSuitesTests {

    @Test("Given test files, when the suites are read, then only files declaring a type of their own name count")
    func onlyFilesDeclaringTheirOwnTypeCount() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let declared = dir.appendingPathComponent("FooTests.swift")
        let renamed = dir.appendingPathComponent("BarTests.swift")
        let helper = dir.appendingPathComponent("Helpers.swift")
        let notText = dir.appendingPathComponent("BazTests.swift")
        try "@Suite struct FooTests {}".write(to: declared, atomically: true, encoding: .utf8)
        try "final class BarSpecs: XCTestCase {}".write(to: renamed, atomically: true, encoding: .utf8)
        try "struct Helpers {}".write(to: helper, atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: notText)

        let suites = TargetedSuites.declared(in: [declared, renamed, helper, notText].map(\.path))

        #expect(Set(suites.keys) == ["FooTests"])
    }

    @Test("Given a source file, when its suite is looked up, then it is the file's name plus Tests when declared")
    func aSourceMapsToItsSuiteWhenDeclared() {
        let suites = ["FooTests": TargetedSuite(name: "FooTests", testTarget: "PkgTests")]

        #expect(TargetedSuites.suite(for: "/proj/Sources/Foo.swift", among: suites)?.name == "FooTests")
        #expect(TargetedSuites.suite(for: "/proj/Sources/Bar.swift", among: suites) == nil)
    }

    @Test("Given a test file under Tests/<Target>/, when its suite is read, then it knows its test target")
    func aDeclaredSuiteKnowsItsTestTarget() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let file = dir.appendingPathComponent("Tests/CoreATests/FooTests.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "@Suite struct FooTests {}".write(to: file, atomically: true, encoding: .utf8)

        let suites = TargetedSuites.declared(in: [file.path])

        #expect(suites["FooTests"] == TargetedSuite(name: "FooTests", testTarget: "CoreATests"))
    }

    @Test(
        "Given a test file path, when its test target is read, then it is the directory right under Tests",
        arguments: [
            ("/p/Tests/CoreATests/AdderTests.swift", "CoreATests"),
            ("/p/Tests/CoreATests/Nested/AdderTests.swift", "CoreATests"),
            ("/p/Tests/Outer/Tests/Inner/AdderTests.swift", "Inner"),
            ("/p/Tests/AdderTests.swift", nil),
            ("/p/Sources/AppTests/AdderTests.swift", nil),
        ]
    )
    func testTargetIsTheDirectoryUnderTests(path: String, expected: String?) {
        #expect(TargetedSuites.testTarget(of: path) == expected)
    }

    @Test("Given contents handed in, when suites are declared, then they are read from them and not from disk")
    func suitesAreReadFromTheContentsGiven() {
        let suites = TargetedSuites.declared(
            in: ["/nowhere/Tests/AppTests/CalcTests.swift", "/nowhere/Tests/AppTests/OtherTests.swift"],
            read: { $0.hasSuffix("CalcTests.swift") ? "struct CalcTests {}" : nil }
        )

        #expect(suites == ["CalcTests": TargetedSuite(name: "CalcTests", testTarget: "AppTests")])
    }
}
