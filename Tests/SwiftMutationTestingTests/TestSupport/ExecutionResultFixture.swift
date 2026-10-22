@testable import SwiftMutationTesting

func makeExecutionResult(
    id: String = "m0",
    filePath: String = "/tmp/Foo.swift",
    line: Int = 1,
    column: Int = 1,
    utf8Offset: Int = 0,
    status: ExecutionStatus,
    testDuration: Double = 0,
    killerTestFile: String? = nil,
    operatorIdentifier: String = "ArithmeticOperatorReplacement",
    fingerprint: String = "fingerprint",
    activated: Bool? = nil,
    unconfirmedKiller: String? = nil,
    fromCache: Bool = false
) -> ExecutionResult {
    ExecutionResult(
        descriptor: makeMutantDescriptor(
            id: id,
            filePath: filePath,
            line: line,
            column: column,
            utf8Offset: utf8Offset,
            operatorIdentifier: operatorIdentifier,
            fingerprint: fingerprint
        ),
        status: status,
        testDuration: testDuration,
        killerTestFile: killerTestFile,
        activated: activated,
        unconfirmedKiller: unconfirmedKiller,
        fromCache: fromCache
    )
}
