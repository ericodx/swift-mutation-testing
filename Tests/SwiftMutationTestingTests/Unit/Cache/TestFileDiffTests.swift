import Testing

@testable import SwiftMutationTesting

@Suite("TestFileDiff")
struct TestFileDiffTests {
    @Test("Given empty sets, when hasChanges checked, then returns false")
    func hasChangesReturnsFalseWhenAllSetsEmpty() {
        let diff = TestFileDiff(added: [], modified: [], removed: [])

        #expect(!diff.hasChanges)
    }

    @Test("Given added files, when hasChanges checked, then returns true")
    func hasChangesReturnsTrueWhenFilesAdded() {
        let diff = TestFileDiff(added: ["NewTests.swift"], modified: [], removed: [])

        #expect(diff.hasChanges)
    }

    @Test("Given modified files, when hasChanges checked, then returns true")
    func hasChangesReturnsTrueWhenFilesModified() {
        let diff = TestFileDiff(added: [], modified: ["FooTests.swift"], removed: [])

        #expect(diff.hasChanges)
    }

    @Test("Given removed files, when hasChanges checked, then returns true")
    func hasChangesReturnsTrueWhenFilesRemoved() {
        let diff = TestFileDiff(added: [], modified: [], removed: ["OldTests.swift"])

        #expect(diff.hasChanges)
    }
}
