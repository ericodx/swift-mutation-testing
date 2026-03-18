import Foundation

struct DetectedProject: Sendable {

    static let empty = DetectedProject(scheme: nil, allSchemes: [])

    let scheme: String?
    let allSchemes: [String]
}

struct ProjectDetector: Sendable {
    let launcher: any ProcessLaunching

    func detect(at projectPath: String) async -> DetectedProject {
        let projectURL = URL(fileURLWithPath: projectPath)

        guard let container = findContainer(in: projectURL) else {
            return .empty
        }

        let schemes = await listSchemes(container: container, workingDirectory: projectURL)
        return DetectedProject(scheme: schemes.first, allSchemes: schemes)
    }

    private func findContainer(in projectURL: URL) -> (flag: String, path: String)? {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: projectURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else {
            return nil
        }

        if let workspace = items.first(where: { $0.pathExtension == "xcworkspace" }) {
            return ("-workspace", workspace.path)
        }

        if let project = items.first(where: { $0.pathExtension == "xcodeproj" }) {
            return ("-project", project.path)
        }

        return nil
    }

    private func listSchemes(
        container: (flag: String, path: String),
        workingDirectory: URL
    ) async -> [String] {
        guard
            let result = try? await launcher.launchCapturing(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: [container.flag, container.path, "-list", "-json"],
                environment: nil,
                workingDirectoryURL: workingDirectory,
                timeout: 30
            ),
            result.exitCode == 0
        else {
            return []
        }

        return parseSchemes(from: result.output)
    }

    private func parseSchemes(from output: String) -> [String] {
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        let container =
            json["workspace"] as? [String: Any]
            ?? json["project"] as? [String: Any]

        return container?["schemes"] as? [String] ?? []
    }
}
