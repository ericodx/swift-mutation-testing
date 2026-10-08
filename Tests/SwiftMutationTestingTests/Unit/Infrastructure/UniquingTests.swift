import Testing

@testable import SwiftMutationTesting

@Suite("Uniquing")
struct UniquingTests {
    @Test("Given a key seen twice, when the pairs are collected, then the first or the last value is kept")
    func firstAndLastKeepTheirSide() {
        let pairs = [("k", 1), ("other", 3), ("k", 2)]

        #expect(Uniquing.keepingFirst(pairs) == ["k": 1, "other": 3])
        #expect(Uniquing.keepingLast(pairs) == ["k": 2, "other": 3])
    }
}
