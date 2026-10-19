import Foundation

@testable import SwiftMutationTesting

actor XcodeBaselineOutcomeMock: ProcessLaunching {

    init(exitCode: Int32, output: String = "") {
        self.exitCode = exitCode
        self.output = output
    }

    private let exitCode: Int32
    private let output: String
    private(set) var mutantTestRuns = 0
    private(set) var baselineRequests: [ProcessRequest] = []
    private(set) var mutantRequests: [ProcessRequest] = []

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
            guard !selectedMutant(in: request).isEmpty else {
                baselineRequests.append(request)
                return (exitCode, output)
            }
            mutantTestRuns += 1
            mutantRequests.append(request)
            return (0, "")

        case "xcresulttool":
            return (1, "")

        default:
            return (0, "")
        }
    }

    private func writeXctestrun(for request: ProcessRequest) {
        guard let index = request.arguments.firstIndex(of: "-derivedDataPath"),
            index + 1 < request.arguments.count
        else { return }

        let products = URL(fileURLWithPath: request.arguments[index + 1]).appendingPathComponent("Build/Products")
        try? FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let plist: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: products.appendingPathComponent("App.xctestrun"))
    }

    private func selectedMutant(in request: ProcessRequest) -> String {
        guard let index = request.arguments.firstIndex(of: "-xctestrun"),
            index + 1 < request.arguments.count,
            let data = FileManager.default.contents(atPath: request.arguments[index + 1]),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let target = plist["MyTarget"] as? [String: Any],
            let environment = target["EnvironmentVariables"] as? [String: String]
        else { return "" }

        return environment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
    }
}
