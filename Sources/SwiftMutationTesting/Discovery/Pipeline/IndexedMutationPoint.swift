struct IndexedMutationPoint: Sendable {
    let index: Int
    let mutation: MutationPoint
    let isSchematizable: Bool
    let fingerprint: String
    var isInLoopCondition = false

    var mutantID: String {
        MutantID.make(index: index)
    }

    func toDescriptor(mutatedContent: String?, sourceContentHash: String) -> MutantDescriptor {
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
            mutatedSourceContent: mutatedContent,
            sourceContentHash: sourceContentHash,
            fingerprint: fingerprint,
            isInLoopCondition: isInLoopCondition
        )
    }
}
