@testable import SwiftMutationTesting

func makeExecutionResult(
    id: String = "m0",
    filePath: String = "/tmp/Foo.swift",
    line: Int = 1,
    column: Int = 1,
    utf8Offset: Int = 0,
    status: ExecutionStatus,
    testDuration: Double = 0,
    killerTestFile: String? = nil
) -> ExecutionResult {
    ExecutionResult(
        descriptor: makeMutantDescriptor(
            id: id,
            filePath: filePath,
            line: line,
            column: column,
            utf8Offset: utf8Offset
        ),
        status: status,
        testDuration: testDuration,
        killerTestFile: killerTestFile
    )
}
