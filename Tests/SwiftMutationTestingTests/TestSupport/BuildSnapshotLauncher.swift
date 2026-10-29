import Foundation

@testable import SwiftMutationTesting

actor BuildSnapshotLauncher: ProcessLaunching {
    struct Build: Equatable {
        let root: String
        let schematized: [String]
    }

    private let base: any ProcessLaunching
    private(set) var builds: [Build] = []

    init(base: any ProcessLaunching) {
        self.base = base
    }

    var roots: Set<String> { Set(builds.map(\.root)) }

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
        if Self.isBuild(request) {
            builds.append(
                Build(
                    root: request.workingDirectoryURL.path,
                    schematized: Self.regularSwiftFiles(under: request.workingDirectoryURL)
                )
            )
        }
        return try await base.launchCapturing(request)
    }

    private static func isBuild(_ request: ProcessRequest) -> Bool {
        switch request.executableURL.lastPathComponent {
        case "xcodebuild": request.arguments.first == "build-for-testing"
        case "swift": request.arguments.first == "build"
        default: false
        }
    }

    private static func regularSwiftFiles(under root: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
        var names: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            if !isSymlink { names.append(url.lastPathComponent) }
        }
        return names.sorted()
    }
}
