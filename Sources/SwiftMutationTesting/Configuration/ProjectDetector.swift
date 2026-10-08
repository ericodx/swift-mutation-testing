import Foundation

struct ProjectDetector: Sendable {
    let launcher: any ProcessLaunching
    var fileSystem = FileSystem()

    func detect(at projectPath: String) async -> DetectedProject {
        let projectURL = URL(fileURLWithPath: fileSystem.projectPath(projectPath))

        let found = XcodeContainerLocator.candidates(in: projectURL, fileSystem: fileSystem)
        if !found.workspaces.isEmpty || !found.projects.isEmpty {
            return await detectXcode(at: projectURL, candidates: found)
        }

        let hasPackage = fileSystem.fileExists(projectURL.appendingPathComponent("Package.swift").path)
        let nested = XcodeContainerLocator.nestedCandidates(in: projectURL, fileSystem: fileSystem)
        if !hasPackage, !nested.workspaces.isEmpty || !nested.projects.isEmpty {
            return await detectXcode(at: projectURL, candidates: nested)
        }

        if hasPackage {
            let testTargets = await listSPMTestTargets(in: projectURL)
            return DetectedProject(
                kind: .spm(testTargets: testTargets),
                testTarget: testTargets.first,
                testingFramework: .swiftTesting
            )
        }

        return .empty
    }

    private func detectXcode(at projectURL: URL, candidates: XcodeContainerLocator.Candidates) async -> DetectedProject
    {
        let container: XcodeContainer?
        var note: String?
        do {
            container = try XcodeContainerLocator.locate(
                in: projectURL, workspace: nil, project: nil, fileSystem: fileSystem)
        } catch {
            container = nil
            note = error.message
        }

        var schemes: [String] = []
        var projectName: String?
        var testTarget: String?
        if let container {
            let flag = container.arguments[0]
            let path = projectURL.appendingPathComponent(container.path).path
            (schemes, projectName, testTarget) = await listProject(
                container: (flag, path), workingDirectory: projectURL)
        }
        let destination = await detectDestination(in: projectURL, container: container)
        var detected = DetectedProject(
            kind: .xcode(
                scheme: selectScheme(from: schemes, projectName: projectName),
                allSchemes: schemes,
                destination: destination
            ),
            testTarget: testTarget,
            testingFramework: detectTestingFramework(at: projectURL, testTarget: testTarget)
        )
        detected.xcodeContainer = container
        detected.containerNote = note
        if note != nil {
            detected.containerCandidates =
                candidates.workspaces.map(XcodeContainer.workspace) + candidates.projects.map(XcodeContainer.project)
        }
        return detected
    }

    private func listProject(
        container: (flag: String, path: String),
        workingDirectory: URL
    ) async -> (schemes: [String], projectName: String?, testTarget: String?) {
        guard
            let result = try? await launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                    arguments: [container.flag, container.path, "-list", "-json"],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: workingDirectory,
                    timeout: 30
                )
            ),
            result.exitCode == 0
        else {
            return ([], nil, nil)
        }

        return parseListOutput(result.output)
    }

    private func listSPMTestTargets(in projectURL: URL) async -> [String] {
        guard
            let result = try? await launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                    arguments: ["package", "dump-package"],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: projectURL,
                    timeout: 30
                )
            ),
            result.exitCode == 0,
            let data = result.output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let targets = json["targets"] as? [[String: Any]]
        else {
            return []
        }

        return
            targets
            .filter { ($0["type"] as? String) == "test" }
            .compactMap { $0["name"] as? String }
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

    private func detectDestination(in projectURL: URL, container: XcodeContainer?) async -> String {
        let projectPath: String? =
            switch container {
            case .project(let path): path
            case .workspace(let path): XcodeContainerLocator.projects(referencedBy: path, in: projectURL).first
            case nil: XcodeContainerLocator.candidates(in: projectURL, fileSystem: fileSystem).projects.first
            }
        guard
            let projectPath,
            let content = try? String(
                contentsOf: projectURL.appendingPathComponent(projectPath).appendingPathComponent("project.pbxproj"),
                encoding: .utf8
            )
        else {
            return "platform=macOS"
        }

        for simulator in Self.simulatorPlatforms
        where content.range(of: #"SDKROOT\s*=\s*"# + simulator.sdkroot, options: .regularExpression) != nil {
            if let device = await queryBestDevice(for: simulator.platform, selecting: simulator.selecting) {
                return "platform=\(simulator.platform) Simulator,OS=latest,name=\(device)"
            }
        }

        return "platform=macOS"
    }

    private struct SimulatorPlatform: Sendable {
        let sdkroot: String
        let platform: String
        let selecting: @Sendable ([String]) -> String?
    }

    private static let simulatorPlatforms: [SimulatorPlatform] = [
        SimulatorPlatform(sdkroot: "iphoneos", platform: "iOS") {
            $0.first { $0.hasPrefix("iPhone") && $0.contains("Pro") } ?? $0.first { $0.hasPrefix("iPhone") }
        },
        SimulatorPlatform(sdkroot: "appletvos", platform: "tvOS") {
            $0.first { $0.contains("Apple TV 4K") } ?? $0.first { $0.contains("Apple TV") }
        },
        SimulatorPlatform(sdkroot: "watchos", platform: "watchOS") { $0.first { $0.contains("Apple Watch") } },
        SimulatorPlatform(sdkroot: "xros", platform: "visionOS") { $0.first { $0.contains("Apple Vision Pro") } },
    ]

    private func queryBestDevice(for platform: String, selecting: ([String]) -> String?) async -> String? {
        guard
            let result = try? await launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                    arguments: ["simctl", "list", "devices", "available", "--json"],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: URL(fileURLWithPath: "."),
                    timeout: 10
                )
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
            if let name = selecting(names) { return name }
        }

        return nil
    }

    private func detectTestingFramework(at projectURL: URL, testTarget: String?) -> TestingFramework {
        let searchURL: URL
        if let testTarget {
            let targetURL = projectURL.appendingPathComponent(testTarget)
            searchURL = fileSystem.fileExists(targetURL.path) ? targetURL : projectURL
        } else {
            searchURL = projectURL
        }

        let enumerator = FileManager.default.enumerator(
            at: searchURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var hasXCTest = false
        var hasSwiftTesting = false

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            if content.contains("import XCTest") { hasXCTest = true }
            if content.contains("import Testing") { hasSwiftTesting = true }

            if hasXCTest && hasSwiftTesting { break }
        }

        if hasXCTest && !hasSwiftTesting { return .xctest }
        return .swiftTesting
    }

    private func runtimeVersion(from key: String) -> (Int, Int) {
        let parts = key.components(separatedBy: "-")
        guard parts.count >= 2,
            let major = Int(parts[parts.count - 2]),
            let minor = Int(parts[parts.count - 1])
        else { return (0, 0) }
        return (major, minor)
    }
}
