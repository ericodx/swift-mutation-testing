import Testing

@testable import SwiftMutationTesting

@Suite("KillerTestFilter")
struct KillerTestFilterTests {

    @Test(
        "Given a Swift Testing function name, when filtered, then the name is matched literally",
        arguments: [
            ("roundTripsAFixtureFile()", #"roundTripsAFixtureFile\(\)"#),
            ("check(value:limit:)", #"check\(value:limit:\)"#),
        ]
    )
    func aFunctionNameIsEscaped(killer: String, filter: String) {
        #expect(KillerTestFilter.filter(for: killer) == filter)
    }

    @Test(
        "Given an XCTest name, when filtered, then the test is separated from its class by a slash",
        arguments: [
            ("muterTests.InitTests.test_createsAFile", "muterTests.InitTests/test_createsAFile"),
            ("RealTests.testAdd", "RealTests/testAdd"),
        ]
    )
    func anXCTestNameNamesItsClass(killer: String, filter: String) {
        #expect(KillerTestFilter.filter(for: killer) == filter)
    }

    @Test(
        "Given a name that does not identify one test, when filtered, then there is no filter",
        arguments: ["a check", "Given a file, when read, then it parses", "testAdd", "", "f(x) and more"]
    )
    func anUnidentifiableNameHasNoFilter(killer: String) {
        #expect(KillerTestFilter.filter(for: killer) == nil)
    }
}
