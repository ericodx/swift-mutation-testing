import XCTest

@testable import CalcApp

final class CalcAppTests: XCTestCase {
    func testAdd() {
        XCTAssertEqual(Calculator().add(2, 3), 5)
    }

    func testSubtract() {
        XCTAssertEqual(Calculator().subtract(5, 3), 2)
    }

    func testIsPositive() {
        XCTAssertTrue(Calculator().isPositive(1))
    }

    func testIsInRange() {
        XCTAssertTrue(Validator().isInRange(50))
        XCTAssertFalse(Validator().isInRange(-1))
        XCTAssertTrue(Validator().isInRange(0))
    }
}
