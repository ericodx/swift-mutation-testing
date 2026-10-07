import Testing

@testable import SwiftMutationTesting

@Suite("OperatorRegistry")
struct OperatorRegistryTests {
    @Test("Given the experimental tier, when its operators are listed, then every operator is there, in registry order")
    func theExperimentalTierHoldsEveryOperator() {
        #expect(OperatorRegistry.operatorNames(upTo: .experimental) == OperatorRegistry.allOperatorNames)
    }

    @Test("Given the tiers of the record campaign, when each is listed, then it holds the operators assigned to it")
    func theTiersAreTheCampaignsAssignments() {
        #expect(
            OperatorRegistry.operatorNames(upTo: .conservative) == [
                "LogicalOperatorReplacement", "NegateConditional", "SwapTernary",
            ]
        )
        #expect(
            OperatorRegistry.operatorNames(upTo: .standard) == OperatorRegistry.operatorNames(upTo: .conservative)
        )
        #expect(OperatorRegistry.operatorNames(upTo: .experimental).count == 7)
    }

    @Test("Given each tier, when its operators are listed, then the lower tier's set is inside the higher one's")
    func lowerTiersAreInsideHigherOnes() {
        let conservative = OperatorRegistry.operatorNames(upTo: .conservative)
        let standard = OperatorRegistry.operatorNames(upTo: .standard)
        let experimental = OperatorRegistry.operatorNames(upTo: .experimental)

        #expect(conservative.allSatisfy { standard.contains($0) })
        #expect(standard.allSatisfy { experimental.contains($0) })
    }

    @Test("Given every registered operator, when its SARIF rule is made, then the operator's own texts describe it")
    func everyOperatorDescribesItself() {
        for name in OperatorRegistry.allOperatorNames {
            let rule = SarifRuleCatalog.rule(for: name)

            #expect(rule.shortDescription.text != name)
            #expect(rule.fullDescription.text != "Mutates the code.")
            #expect(OperatorRegistry.operator(named: name)?.summary == rule.shortDescription.text)
        }
    }

    @Test("Given the registry, when the loop-risky operators are listed, then they are the two that can hang a loop")
    func theLoopRiskyOperatorsAreArithmeticAndSideEffects() {
        #expect(OperatorRegistry.loopRiskyNames == ["ArithmeticOperatorReplacement", "RemoveSideEffects"])
    }

    @Test("Given a name no operator has, when looked up, then there is none")
    func anUnknownNameNamesNoOperator() {
        #expect(OperatorRegistry.operator(named: "FutureOperator") == nil)
    }

    @Test("Given operator names, when the operators are built, then each one reports the name it was asked by")
    func operatorsComeBackUnderTheirNames() {
        let names = ["SwapTernary", "NegateConditional"]

        #expect(OperatorRegistry.operators(named: names).map(\.identifier) == ["NegateConditional", "SwapTernary"])
        #expect(OperatorRegistry.operators(named: []).map(\.identifier) == OperatorRegistry.allOperatorNames)
    }
}
