import Foundation

@testable import SwiftMutationTesting

actor FallbackBuildSucceedingMock: ProcessLaunching {
    private var captureCount = 0

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
        captureCount += 1
        if captureCount == 1 { return (1, "") }
        if let idx = request.arguments.firstIndex(of: "-derivedDataPath"),
            idx + 1 < request.arguments.count
        {
            let productsURL = URL(fileURLWithPath: request.arguments[idx + 1])
                .appendingPathComponent("Build/Products")
            try? FileManager.default.createDirectory(at: productsURL, withIntermediateDirectories: true)
            let plist: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: productsURL.appendingPathComponent("fake.xctestrun"))
        }
        return (0, "")
    }
}
