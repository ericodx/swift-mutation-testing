import Testing

@testable import SwiftMutationTesting

@Suite("SchemataGenerator — edits")
struct SchemataGeneratorEditsTests {
    @Test("Given no edit, when an offset is mapped, then it is unchanged")
    func noEditLeavesOffsets() {
        let edits = SchemataGenerator.Edits()

        #expect(edits.isEmpty)
        #expect(edits.current(42) == 42)
    }

    @Test("Given edits recorded from the end of the file back, when offsets are mapped, then only earlier edits count")
    func onlyEditsBeforeAnOffsetShiftIt() {
        var edits = SchemataGenerator.Edits()
        edits.record(start: 300, delta: 50)
        edits.record(start: 200, delta: -10)
        edits.record(start: 100, delta: 7)

        #expect(edits.current(50) == 50)
        #expect(edits.current(100) == 100)
        #expect(edits.current(150) == 157)
        #expect(edits.current(250) == 247)
        #expect(edits.current(301) == 348)
    }
}
