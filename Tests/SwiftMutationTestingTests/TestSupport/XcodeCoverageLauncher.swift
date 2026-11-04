import Foundation

@testable import SwiftMutationTesting

actor XcodeCoverageLauncher: ProcessLaunching {
    struct Run: Equatable {
        let mutantID: String
        let onlyTesting: [String]
    }

    private let sitesByTest: [String: [String]]
    private let outside: [String]
    private(set) var runs: [Run] = []
    private(set) var baselines: [[String]] = []
    private(set) var baselineEnvironments: [[String: String]] = []

    init(sitesByTest: [String: [String]], outside: [String] = []) {
        self.sitesByTest = sitesByTest
        self.outside = outside
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()

        switch request.arguments.first {
        case "build-for-testing":
            writeXctestrun(for: request)
            return (0, "")

        case "test-without-building":
            let environment = environment(of: request)
            let mutantID = environment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
            guard mutantID.isEmpty else {
                runs.append(Run(mutantID: mutantID, onlyTesting: Self.selection(of: request)))
                return (0, "")
            }
            baselines.append(request.arguments)
            baselineEnvironments.append(environment)
            if let path = environment[SupportDeclarations.coverageEnvironmentVariable] {
                try? collected().write(toFile: path, atomically: true, encoding: .utf8)
                return (0, "Test Suite 'All tests' started at 2026-11-03.\n◇ Test run started.")
            }
            return (0, "Test Suite 'All tests' passed at 2026-11-03.")

        case "xcresulttool":
            let nodes = sitesByTest.keys.sorted().map {
                "{\"nodeType\":\"Test Case\",\"nodeIdentifierURL\":\"test://com.apple.xcode/App/AppTests/\($0)\"}"
            }
            return (0, "{\"testNodes\":[\(nodes.joined(separator: ","))]}")

        default:
            return (0, "")
        }
    }

    // MARK: - Private

    private func collected() -> String {
        var lines = outside.map { "\(SupportDeclarations.reachedMarker) \($0)" }
        for (test, sites) in sitesByTest.sorted(by: { $0.key < $1.key }) {
            let path = test.split(separator: "/")
            lines += path.dropLast().map { "XCTestOutputBarrier◇ Suite \($0) started." }
            lines.append("XCTestOutputBarrier◇ Test \(path.last ?? "") started.")
            lines += sites.map { "\(SupportDeclarations.reachedMarker) \($0)" }
            lines.append("✔ Test \(path.last ?? "") passed after 0.001 seconds.")
            lines += path.dropLast().reversed().map { "✔ Suite \($0) passed after 0.001 seconds." }
        }
        return lines.joined(separator: "\n")
    }

    private func writeXctestrun(for request: ProcessRequest) {
        guard let index = request.arguments.firstIndex(of: "-derivedDataPath"),
            index + 1 < request.arguments.count
        else { return }

        let products = URL(fileURLWithPath: request.arguments[index + 1]).appendingPathComponent("Build/Products")
        try? FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "TestConfigurations": [
                [
                    "TestTargets": [
                        [
                            "BlueprintName": "AppTests", "ProductModuleName": "AppTests",
                            "TestBundlePath": "__TESTROOT__/Debug/AppTests.xctest",
                            "EnvironmentVariables": [String: String](),
                        ]
                    ]
                ]
            ]
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: products.appendingPathComponent("App.xctestrun"))
    }

    private func environment(of request: ProcessRequest) -> [String: String] {
        guard let index = request.arguments.firstIndex(of: "-xctestrun"),
            index + 1 < request.arguments.count,
            let data = FileManager.default.contents(atPath: request.arguments[index + 1]),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let configurations = plist["TestConfigurations"] as? [[String: Any]],
            let targets = configurations.first?["TestTargets"] as? [[String: Any]],
            let environment = targets.first?["EnvironmentVariables"] as? [String: String]
        else { return [:] }

        return environment
    }

    private static func selection(of request: ProcessRequest) -> [String] {
        request.arguments.enumerated().compactMap { index, argument in
            index > 0 && request.arguments[index - 1] == "-only-testing" ? argument : nil
        }
    }
}
