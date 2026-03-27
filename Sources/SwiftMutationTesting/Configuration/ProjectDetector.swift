import Foundation

struct ProjectDetector: Sendable {
    let launcher: any ProcessLaunching

    func detect(at projectPath: String) async -> DetectedProject {
        let projectURL = resolvedURL(for: projectPath)

        guard let container = findContainer(in: projectURL) else {
            return .empty
        }

        let (schemes, projectName, testTarget) = await listProject(container: container, workingDirectory: projectURL)
        let destination = await detectDestination(in: projectURL)

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

    private func detectDestination(in projectURL: URL) async -> String {
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

        if content.range(of: #"SDKROOT\s*=\s*iphoneos"#, options: .regularExpression) != nil,
            let device = await queryBestDevice(for: "iOS")
        {
            return "platform=iOS Simulator,OS=latest,name=\(device)"
        }

        if content.range(of: #"SDKROOT\s*=\s*appletvos"#, options: .regularExpression) != nil,
            let device = await queryBestDevice(for: "tvOS")
        {
            return "platform=tvOS Simulator,OS=latest,name=\(device)"
        }

        if content.range(of: #"SDKROOT\s*=\s*watchos"#, options: .regularExpression) != nil,
            let device = await queryBestDevice(for: "watchOS")
        {
            return "platform=watchOS Simulator,OS=latest,name=\(device)"
        }

        return "platform=macOS"
    }

    private func queryBestDevice(for platform: String) async -> String? {
        guard
            let result = try? await launcher.launchCapturing(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "devices", "available", "--json"],
                environment: nil,
                workingDirectoryURL: URL(fileURLWithPath: "."),
                timeout: 10
            ),
            result.exitCode == 0,
            let data = result.output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = json["devices"] as? [String: Any]
        else {
            return nil
        }

        let runtimeKey = ".\(platform)-"
        let sorted = devices.keys
            .filter { $0.contains(runtimeKey) }
            .sorted { runtimeVersion(from: $0) > runtimeVersion(from: $1) }

        for key in sorted {
            guard let deviceList = devices[key] as? [[String: Any]] else { continue }
            let names = deviceList.compactMap { $0["name"] as? String }
            if let name = preferredDevice(from: names, for: platform) {
                return name
            }
        }

        return nil
    }

    private func runtimeVersion(from key: String) -> (Int, Int) {
        let parts = key.components(separatedBy: "-")
        guard parts.count >= 2,
            let major = Int(parts[parts.count - 2]),
            let minor = Int(parts[parts.count - 1])
        else { return (0, 0) }
        return (major, minor)
    }

    private func preferredDevice(from names: [String], for platform: String) -> String? {
        if platform == "iOS" {
            return names.first { $0.hasPrefix("iPhone") && $0.contains("Pro") }
                ?? names.first { $0.hasPrefix("iPhone") }
        }

        if platform == "tvOS" {
            return names.first { $0.contains("Apple TV 4K") }
                ?? names.first { $0.contains("Apple TV") }
        }

        if platform == "watchOS" {
            return names.first { $0.contains("Apple Watch") }
        }

        return nil
    }

}
