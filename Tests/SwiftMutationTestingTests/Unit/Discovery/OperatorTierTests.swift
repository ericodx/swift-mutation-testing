import Testing

@testable import SwiftMutationTesting

@Suite("OperatorTier")
struct OperatorTierTests {

    @Test("Given the three tiers, when compared, then conservative precedes default and default precedes experimental")
    func tiersAreOrderedFromConservativeToExperimental() {
        #expect(OperatorTier.conservative < .standard)
        #expect(OperatorTier.standard < .experimental)
        #expect(OperatorTier.allCases == [.conservative, .standard, .experimental])
    }

    @Test("Given a tier's name, when read, then it is the tier", arguments: OperatorTier.allCases)
    func aTierIsReadFromItsName(tier: OperatorTier) {
        #expect(OperatorTier(rawValue: tier.rawValue) == tier)
    }

    @Test("Given the name users write for the middle tier, when read, then it is the standard tier")
    func theMiddleTierIsStillCalledDefault() {
        #expect(OperatorTier(rawValue: "default") == .standard)
        #expect(OperatorTier.standard.rawValue == "default")
    }

    @Test("Given a name that is no tier, when read, then there is none")
    func anUnknownNameIsNoTier() {
        #expect(OperatorTier(rawValue: "stable") == nil)
    }
}
