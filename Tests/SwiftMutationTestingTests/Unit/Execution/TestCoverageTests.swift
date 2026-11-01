import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestCoverage")
struct TestCoverageTests {
    private let xctest = "Test Case '-[PkgTests.AddTests testAdd]' started."
    private let xctestPassed = "Test Case '-[PkgTests.AddTests testAdd]' passed (0.001 seconds)."
    private let record = SupportDeclarations.reachedMarker + " abcd1234:9"

    private func event(_ kind: String, _ id: String) -> String {
        "{\"kind\":\"event\",\"payload\":{\"instant\":{\"absolute\":1,\"since1970\":2},\"kind\":\"\(kind)\","
            + "\"messages\":[],\"testID\":\"\(id)\"},\"version\":0}"
    }

    @Test("Given records between an XCTest start and end, when parsed, then the site is reached by that test")
    func recordsInsideAnXCTestWindowBelongToIt() {
        let output = [xctest, record, record, xctestPassed, "Test Suite 'All tests' passed"].joined(separator: "\n")

        let coverage = CoverageOutputParser().parse(output)

        #expect(coverage.sites == ["abcd1234:9": [TestReference(library: .xctest, id: "PkgTests.AddTests/testAdd")]])
        #expect(coverage.outside.isEmpty)
    }

    @Test("Given records inside a Swift Testing test event window, when parsed, then the test id loses its location")
    func recordsInsideASwiftTestingWindowBelongToTheTest() {
        let id = "PkgTests.AddSuite/plus()/AddTests.swift:5:6"
        let output = [
            event("testStarted", "PkgTests.AddSuite"), event("testStarted", id), record, event("testEnded", id),
            event("testEnded", "PkgTests.AddSuite"),
        ].joined(separator: "\n")

        let coverage = CoverageOutputParser().parse(output)

        let test = TestReference(library: .swiftTesting, id: "PkgTests.AddSuite/plus()")
        #expect(coverage.sites == ["abcd1234:9": [test]])
    }

    @Test("Given a record before any test and one after the last, when parsed, then the site is outside")
    func recordsOutsideEveryWindowAreOutside() {
        let other = SupportDeclarations.reachedMarker + " abcd1234:40"
        let output = [record, xctest, xctestPassed, other].joined(separator: "\n")

        let coverage = CoverageOutputParser().parse(output)

        #expect(coverage.outside == ["abcd1234:9", "abcd1234:40"])
        #expect(coverage.sites["abcd1234:9"] == [])
    }

    @Test("Given two tests reaching the same site, when parsed, then both are listed once each in order")
    func everyReachingTestIsListedOnce() {
        let second = "Test Case '-[PkgTests.AddTests testMore]' started."
        let output = [xctest, record, record, xctestPassed, second, record].joined(separator: "\n")

        let coverage = CoverageOutputParser().parse(output)

        #expect(
            coverage.sites["abcd1234:9"]?.map(\.id) == ["PkgTests.AddTests/testAdd", "PkgTests.AddTests/testMore"]
        )
    }

    @Test("Given a mutant, when its reach is asked, then an unlisted site is unreached and an outside one unknown")
    func reachOfAMutant() {
        let path = "/p/Sources/A.swift"
        let suffix = SupportDeclarations.suffix(for: path)
        let test = TestReference(library: .xctest, id: "PkgTests.ATests/testA")
        let coverage = TestCoverage(
            sites: [TestCoverage.key(suffix: suffix, site: 9): [test], TestCoverage.key(suffix: suffix, site: 40): []],
            outside: [TestCoverage.key(suffix: suffix, site: 40)]
        )

        #expect(coverage.reach(of: makeMutantDescriptor(filePath: path, functionBodyStart: 9)) == .tests([test]))
        #expect(coverage.reach(of: makeMutantDescriptor(filePath: path, functionBodyStart: 40)) == .unknown)
        #expect(coverage.reach(of: makeMutantDescriptor(filePath: path, functionBodyStart: 70)) == .unreached)
        #expect(coverage.reach(of: makeMutantDescriptor(filePath: path)) == .unknown)
    }

    @Test("Given two maps, when merged, then their tests are joined without duplicates and outside sites kept")
    func mergeJoinsTests() {
        let a = TestReference(library: .xctest, id: "T/a")
        let b = TestReference(library: .xctest, id: "T/b")
        var first = TestCoverage(sites: ["k:1": [a]], outside: ["k:2"])

        first.merge(TestCoverage(sites: ["k:1": [a, b], "k:3": []], outside: ["k:3"]))

        #expect(first.sites == ["k:1": [a, b], "k:3": []])
        #expect(first.outside == ["k:2", "k:3"])
    }

    @Test("Given a test reference, when its module is asked, then it is the part before the first dot")
    func moduleOfAReference() {
        #expect(TestReference(library: .xctest, id: "PkgTests.ATests/testA").module == "PkgTests")
        #expect(TestReference(library: .swiftTesting, id: "PkgTests.S/f()").module == "PkgTests")
        #expect(TestReference(library: .xctest, id: "ATests/testA").module == nil)
    }

    @Test("Given test ids, when the location is removed, then only a trailing file position goes")
    func testIDWithoutLocation() {
        #expect(CoverageOutputParser.testID(withoutLocation: "M.S/f()/S.swift:5:6") == "M.S/f()")
        #expect(CoverageOutputParser.testID(withoutLocation: "M.S/f(x:)") == "M.S/f(x:)")
        #expect(CoverageOutputParser.testID(withoutLocation: "M.S") == nil)
    }
}
