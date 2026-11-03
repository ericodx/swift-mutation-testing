import Foundation

@testable import SwiftMutationTesting

actor CoverageLauncher: ProcessLaunching {
    struct Run: Equatable {
        let mutantID: String
        let filters: [String]
    }

    static let bundle = "CoreTests"

    private let sitesByTest: [String: [String]]
    private let outside: [String]
    private let killers: Set<String>
    private(set) var runs: [Run] = []
    private(set) var baselines: [Bool] = []

    init(sitesByTest: [String: [String]], outside: [String] = [], killers: Set<String> = []) {
        self.sitesByTest = sitesByTest
        self.outside = outside
        self.killers = killers
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()
        if request.arguments.first == "build" {
            let macOS = request.workingDirectoryURL
                .appendingPathComponent(".build/out/Products/Debug/\(Self.bundle).xctest/Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: macOS.appendingPathComponent(Self.bundle).path, contents: Data())
            return (0, "")
        }

        if request.arguments.first == "xctest" {
            return (TestBundleInvocation.noTestsExitCode, "")
        }

        guard request.executableURL.lastPathComponent == "swiftpm-testing-helper" else { return (0, "") }

        let mutantID = request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
        let arguments = request.arguments
        let filters = arguments.enumerated().filter { $1 == "--filter" }.map { arguments[$0.offset + 1] }

        if mutantID.isEmpty {
            let collecting = request.additionalEnvironment[SupportDeclarations.coverageEnvironmentVariable] != nil
            baselines.append(collecting)
            return (0, collecting ? collectedOutput() : "✔ Test run with 2 tests in 1 suite passed after 0.1 seconds.")
        }

        runs.append(Run(mutantID: mutantID, filters: filters))
        let selected =
            filters.isEmpty
            ? Array(sitesByTest.keys)
            : sitesByTest.keys.filter { test in
                filters.contains { TestBundleInvocation.swiftTestingFilter(for: "\(Self.bundle).\(test)") == $0 }
            }
        if let killer = selected.sorted().first(where: { killers.contains($0) }) {
            return (1, "✘ Test \"\(killer)\" failed after 0.001 seconds with 1 issue.")
        }
        return (0, "✔ Test run with 2 tests in 1 suite passed after 0.1 seconds.")
    }

    private func collectedOutput() -> String {
        var lines = outside.map { "\(SupportDeclarations.reachedMarker) \($0)" }
        for (test, sites) in sitesByTest.sorted(by: { $0.key < $1.key }) {
            let id = "\(Self.bundle).\(test)/File.swift:1:1"
            lines.append(event("testStarted", id))
            lines += sites.map { "\(SupportDeclarations.reachedMarker) \($0)" }
            lines.append(event("testEnded", id))
        }
        lines.append("✔ Test run with \(sitesByTest.count) tests in 1 suite passed after 0.1 seconds.")
        return lines.joined(separator: "\n")
    }

    private func event(_ kind: String, _ id: String) -> String {
        "{\"kind\":\"event\",\"payload\":{\"instant\":{\"absolute\":1,\"since1970\":2},\"kind\":\"\(kind)\","
            + "\"messages\":[],\"testID\":\"\(id)\"},\"version\":0}"
    }
}
