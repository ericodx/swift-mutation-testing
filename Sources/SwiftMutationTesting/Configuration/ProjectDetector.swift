import Foundation

struct DetectedProject: Sendable {

    static let empty = DetectedProject(
        scheme: nil, allSchemes: [], testTarget: nil, destination: "platform=macOS"
    )

    let scheme: String?
    let allSchemes: [String]
    let testTarget: String?
    let destination: String
}

struct ProjectDetector: Sendable {
    let launcher: any ProcessLaunching

    func detect(at projectPath: String) async -> DetectedProject {
        let projectURL = resolvedURL(for: projectPath)

        guard let container = findContainer(in: projectURL) else {
            return .empty
        }

        let (schemes, projectName, testTarget) = await listProject(container: container, workingDirectory: projectURL)
        let destination = detectDestination(in: projectURL)

        return DetectedProject(
            scheme: selectScheme(from: schemes, projectName: projectName),
            allSchemes: schemes,
            testTarget: testTarget,
            destination: destination
        )
    }

    private func resolvedURL(for path: String) -> URL {
        if path == "." || path.isEmpty {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
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

    private func listProject(
        container: (flag: String, path: String),
        workingDirectory: URL
    ) async -> (schemes: [String], projectName: String?, testTarget: String?) {
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
            return ([], nil, nil)
        }

        return parseListOutput(result.output)
    }

    private func parseListOutput(_ output: String) -> (schemes: [String], projectName: String?, testTarget: String?) {
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ([], nil, nil)
        }

        let container =
            json["workspace"] as? [String: Any]
            ?? json["project"] as? [String: Any]

        let schemes = container?["schemes"] as? [String] ?? []
        let projectName = container?["name"] as? String
        let targets = container?["targets"] as? [String] ?? []
        let candidates = targets.isEmpty ? schemes : targets

        let testTarget =
            candidates.first { $0.hasSuffix("Tests") && !$0.hasSuffix("UITests") }
            ?? candidates.first { $0.hasSuffix("Tests") }

        return (schemes, projectName, testTarget)
    }

    private func selectScheme(from schemes: [String], projectName: String?) -> String? {
        guard let projectName else { return schemes.first }
        return schemes.first { $0 == projectName } ?? schemes.first
    }

    private func detectDestination(in projectURL: URL) -> String {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: projectURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            ),
            let xcodeprojURL = items.first(where: { $0.pathExtension == "xcodeproj" }),
            let content = try? String(
                contentsOf: xcodeprojURL.appendingPathComponent("project.pbxproj"),
                encoding: .utf8
            )
        else {
            return "platform=macOS"
        }

        if content.range(of: #"SDKROOT\s*=\s*iphoneos"#, options: .regularExpression) != nil {
            return "platform=iOS Simulator,OS=latest,name=iPhone 16 Pro"
        }

        if content.range(of: #"SDKROOT\s*=\s*appletvos"#, options: .regularExpression) != nil {
            return "platform=tvOS Simulator,OS=latest,name=Apple TV 4K (3rd generation)"
        }

        if content.range(of: #"SDKROOT\s*=\s*watchos"#, options: .regularExpression) != nil {
            return "platform=watchOS Simulator,OS=latest,name=Apple Watch Series 10 (46mm)"
        }

        return "platform=macOS"
    }
}
