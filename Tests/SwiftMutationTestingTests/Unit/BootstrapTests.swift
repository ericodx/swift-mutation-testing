import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Bootstrap")
struct BootstrapTests {
    @Test("Given all ExecutionStatus cases, when encoded and decoded, then values are equal")
    func executionStatusRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let statuses: [ExecutionStatus] = [
            .killed(by: "testFoo"),
            .killedByCrash,
            .survived,
            .unviable,
            .timeout,
            .noCoverage,
        ]

        for status in statuses {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(ExecutionStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}
