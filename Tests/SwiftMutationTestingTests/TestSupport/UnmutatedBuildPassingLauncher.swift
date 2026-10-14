import Foundation

@testable import SwiftMutationTesting

struct UnmutatedBuildPassingLauncher: ProcessLaunching {
    let base: any ProcessLaunching

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        try await base.launch(
            executableURL: executableURL, arguments: arguments, workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        guard Self.isBuild(request), Self.isUnmutated(request.workingDirectoryURL) else {
            return try await base.launchCapturing(request)
        }
        request.recordActivation()
        return (0, "")
    }

    private static func isBuild(_ request: ProcessRequest) -> Bool {
        switch request.executableURL.lastPathComponent {
        case "xcodebuild": request.arguments.first == "build-for-testing"
        case "swift": request.arguments.first == "build"
        default: false
        }
    }

    private static func isUnmutated(_ sandboxURL: URL) -> Bool {
        let enumerator = FileManager.default.enumerator(
            at: sandboxURL, includingPropertiesForKeys: [.isSymbolicLinkKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            if !isSymlink { return false }
        }
        return true
    }
}
