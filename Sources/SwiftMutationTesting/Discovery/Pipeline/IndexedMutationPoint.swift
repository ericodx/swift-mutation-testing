struct IndexedMutationPoint: Sendable {
    let index: Int
    let mutation: MutationPoint
    let isSchematizable: Bool

    var mutantID: String {
        "swift-mutation-testing_\(index)"
    }

    func toDescriptor(mutatedContent: String?) -> MutantDescriptor {
        MutantDescriptor(
            id: mutantID,
            filePath: mutation.filePath,
            line: mutation.line,
            column: mutation.column,
            utf8Offset: mutation.utf8Offset,
            originalText: mutation.originalText,
            mutatedText: mutation.mutatedText,
            operatorIdentifier: mutation.operatorIdentifier,
            replacementKind: mutation.replacement,
            description: mutation.description,
            isSchematizable: isSchematizable,
            mutatedSourceContent: mutatedContent
        )
    }
}
