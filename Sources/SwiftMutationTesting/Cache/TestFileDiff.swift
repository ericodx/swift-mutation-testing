struct TestFileDiff: Sendable {
    let added: Set<String>
    let modified: Set<String>
    let removed: Set<String>

    var hasChanges: Bool {
        !added.isEmpty || !modified.isEmpty || !removed.isEmpty
    }
}
