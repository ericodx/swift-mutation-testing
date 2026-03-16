import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Bootstrap")
struct BootstrapTests {
    @Test("RunnerInput is decodable")
    func runnerInputDecodable() throws {
        let json = Data(
            """
            {
                "projectPath": "/tmp/MyApp",
                "scheme": "MyApp",
                "destination": "platform=macOS",
                "timeout": 60,
                "concurrency": 4,
                "noCache": false,
                "schematizedFiles": [],
                "supportFileContent": "",
                "mutants": []
            }
            """.utf8)

        let input = try JSONDecoder().decode(RunnerInput.self, from: json)

        #expect(input.scheme == "MyApp")
        #expect(input.mutants.isEmpty)
    }

    @Test("ExecutionStatus roundtrip Codable")
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
