import Foundation

struct BuildStage: Sendable {
    let launcher: any ProcessLaunching

    func build(
        sandbox: Sandbox,
        scheme: String,
        destination: String,
        timeout: Double
    ) async throws -> BuildArtifact {
        let derivedDataURL = sandbox.rootURL.appendingPathComponent(".xmr-derived-data")

        var arguments = [
            "build-for-testing",
            "-scheme", scheme,
            "-destination", destination,
            "-derivedDataPath", derivedDataURL.path,
        ]

        if let workspaceURL = findXcworkspace(in: sandbox.rootURL) {
            arguments += ["-workspace", workspaceURL.path]
        } else if let projectURL = findXcodeproj(in: sandbox.rootURL) {
            arguments += ["-project", projectURL.path]
        }

        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: arguments,
            workingDirectoryURL: sandbox.rootURL,
            timeout: timeout
        )

        guard exitCode == 0 else {
            throw BuildError.compilationFailed
        }

        let productsURL = derivedDataURL.appendingPathComponent("Build/Products")

        guard let xctestrunURL = findXctestrun(in: productsURL) else {
            throw BuildError.xctestrunNotFound
        }

        let data = try Data(contentsOf: xctestrunURL)

        guard let plist = XCTestRunPlist(data) else {
            throw BuildError.xctestrunNotFound
        }

        return BuildArtifact(
            derivedDataPath: derivedDataURL.path,
            xctestrunURL: xctestrunURL,
            plist: plist
        )
    }

    private func findXcworkspace(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        return items.first { $0.pathExtension == "xcworkspace" }
    }

    private func findXcodeproj(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        return items.first { $0.pathExtension == "xcodeproj" }
    }

    private func findXctestrun(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        return items.first { $0.pathExtension == "xctestrun" }
    }
}
