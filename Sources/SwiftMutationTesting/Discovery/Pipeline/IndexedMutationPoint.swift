struct IndexedMutationPoint: Sendable {
    let index: Int
    let mutation: MutationPoint
    let isSchematizable: Bool
}
