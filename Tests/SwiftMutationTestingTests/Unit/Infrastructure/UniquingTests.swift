import Testing

@testable import SwiftMutationTesting

@Suite("Uniquing")
struct UniquingTests {
    @Test("Given a key seen twice, when merged with first or last, then the first or the last value is kept")
    func firstAndLastKeepTheirSide() {
        let pairs = [("k", 1), ("k", 2)]

        #expect(Dictionary(pairs, uniquingKeysWith: Uniquing.first) == ["k": 1])
        #expect(Dictionary(pairs, uniquingKeysWith: Uniquing.last) == ["k": 2])
    }
}
