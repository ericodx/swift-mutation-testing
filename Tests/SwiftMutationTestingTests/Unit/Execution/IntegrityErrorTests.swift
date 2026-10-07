import Testing

@testable import SwiftMutationTesting

@Suite("IntegrityError")
struct IntegrityErrorTests {
    @Test("Given one mutant not applied, when described, then the message names it and says the run stopped")
    func oneMutantNotApplied() {
        let message = IntegrityError.mutantsNotApplied(mutants: ["m0 (Foo.swift:1)"]).errorDescription

        #expect(message?.hasPrefix("1 mutant was not applied to the sandbox: m0 (Foo.swift:1).") == true)
        #expect(message?.contains("The run is stopped") == true)
    }

    @Test("Given many mutants not applied, when described, then ten are listed and the rest counted")
    func manyMutantsNotApplied() {
        let ids = (0 ..< 12).map { "m\($0)" }

        let message = IntegrityError.mutantsNotApplied(mutants: ids).errorDescription

        let listed = "m0, m1, m2, m3, m4, m5, m6, m7, m8, m9 and 2 more"
        #expect(message?.hasPrefix("12 mutants were not applied to the sandbox: \(listed).") == true)
    }

    @Test(
        "Given a schema or support problem, when described, then the message names the file",
        arguments: [
            (IntegrityError.schemaNotApplied(path: "/p/Foo.swift"), "identical to the original"),
            (.supportMissing(path: "/p/Foo.swift"), "does not declare __swiftMutationTestingID"),
            (.sourceNotRestored(path: "/p/Foo.swift"), "could not be linked back to the original"),
        ]
    )
    func fileProblemsNameTheFile(error: IntegrityError, fragment: String) {
        #expect(error.errorDescription?.contains("/p/Foo.swift") == true)
        #expect(error.errorDescription?.contains(fragment) == true)
    }

    @Test("Given kills without any activation, when described, then the message says every verdict is suspect")
    func activationNeverObserved() {
        let message = IntegrityError.activationNeverObserved(killed: 3).errorDescription

        #expect(message?.hasPrefix("3 mutants were killed, but no mutant's code was ever seen running.") == true)
        #expect(message?.contains("every verdict is suspect") == true)
    }
}
