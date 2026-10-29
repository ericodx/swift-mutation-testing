import Testing

@testable import SwiftMutationTesting

@Suite("SlowestFirst")
struct SlowestFirstTests {
    @Test("Given durations for some mutants, when ordered, then the unknown go first and the known longest first")
    func unknownFirstThenLongestFirst() {
        let mutants = (0 ..< 5).map { makeMutantDescriptor(id: "m\($0)") }

        let ordered = SlowestFirst.order(mutants, durations: [2, nil, 30, 7, nil])

        #expect(ordered.map(\.id) == ["m1", "m4", "m2", "m3", "m0"])
    }

    @Test("Given no history, when ordered, then a conditional mutant in a loop condition goes before the rest")
    func likelyLoopsFirstAmongTheUnknown() {
        let mutants = [
            makeMutantDescriptor(id: "m0"),
            makeMutantDescriptor(id: "m1", operatorIdentifier: "NegateConditional", isInLoopCondition: true),
            makeMutantDescriptor(id: "m2", operatorIdentifier: "BooleanLiteralReplacement", isInLoopCondition: true),
            makeMutantDescriptor(id: "m3", operatorIdentifier: "RelationalOperatorReplacement"),
            makeMutantDescriptor(
                id: "m4", operatorIdentifier: "RelationalOperatorReplacement", isInLoopCondition: true
            ),
        ]

        let ordered = SlowestFirst.order(mutants, durations: Array(repeating: nil, count: 5))

        #expect(ordered.map(\.id) == ["m1", "m4", "m0", "m2", "m3"])
    }

    @Test("Given equal durations, when ordered, then the source order is kept between them")
    func tiesKeepTheSourceOrder() {
        let mutants = (0 ..< 4).map { makeMutantDescriptor(id: "m\($0)") }

        let ordered = SlowestFirst.order(mutants, durations: [5, 5, 9, 5])

        #expect(ordered.map(\.id) == ["m2", "m0", "m1", "m3"])
    }

    @Test("Given a mutant with a known duration in a loop condition, when ordered, then its duration decides")
    func aKnownDurationBeatsTheLoopHeuristic() {
        let mutants = [
            makeMutantDescriptor(id: "m0"),
            makeMutantDescriptor(id: "m1", operatorIdentifier: "NegateConditional", isInLoopCondition: true),
        ]

        let ordered = SlowestFirst.order(mutants, durations: [nil, 60])

        #expect(ordered.map(\.id) == ["m0", "m1"])
    }
}
