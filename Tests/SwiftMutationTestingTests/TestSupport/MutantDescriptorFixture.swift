@testable import SwiftMutationTesting

func makeMutantDescriptor(
    id: String = "m0",
    filePath: String = "/tmp/Foo.swift",
    line: Int = 1,
    column: Int = 1,
    utf8Offset: Int = 0,
    originalText: String = "+",
    mutatedText: String = "-",
    operatorIdentifier: String = "ArithmeticOperatorReplacement",
    replacementKind: ReplacementKind = .binaryOperator,
    description: String = "+ → -",
    isSchematizable: Bool = false,
    mutatedSourceContent: String? = nil
) -> MutantDescriptor {
    MutantDescriptor(
        id: id,
        filePath: filePath,
        line: line,
        column: column,
        utf8Offset: utf8Offset,
        originalText: originalText,
        mutatedText: mutatedText,
        operatorIdentifier: operatorIdentifier,
        replacementKind: replacementKind,
        description: description,
        isSchematizable: isSchematizable,
        mutatedSourceContent: mutatedSourceContent
    )
}
