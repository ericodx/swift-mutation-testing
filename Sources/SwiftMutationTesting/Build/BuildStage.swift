import Foundation

struct BuildStage: Sendable {
    let launcher: any ProcessLaunching

    func build(
        sandbox: Sandbox,
        arguments: [String],
        scheme: String,
        destination: String,
        timeout: Double
    ) async throws -> BuildArtifact {
        let derivedDataURL = URL(fileURLWithPath: ToolRequests.derivedDataPath(in: sandbox))

        let (exitCode, buildOutput) = try await run(
            ToolRequests.buildForTesting(
                in: sandbox, scheme: scheme, destination: destination, arguments: arguments, timeout: timeout
            ),
            in: sandbox
        )

        guard exitCode != SPMResultParser.timedOutExitCode else {
            throw BuildError.timedOut(seconds: timeout, output: buildOutput)
        }

        guard exitCode == 0 else {
            throw BuildError.compilationFailed(output: buildOutput)
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

    func buildSPM(
        sandbox: Sandbox,
        timeout: Double
    ) async throws -> BuildArtifact {
        let (exitCode, buildOutput) = try await run(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: timeout), in: sandbox
        )

        guard exitCode != SPMResultParser.timedOutExitCode else {
            throw BuildError.timedOut(seconds: timeout, output: buildOutput)
        }

        guard exitCode == 0 else { throw BuildError.compilationFailed(output: buildOutput) }

        return BuildArtifact(
            derivedDataPath: sandbox.rootURL.appendingPathComponent(".build").path,
            xctestrunURL: nil,
            plist: nil
        )
    }

    func run(_ request: ProcessRequest, in sandbox: Sandbox) async throws -> (exitCode: Int32, output: String) {
        let first = try await launcher.launchCapturing(request)

        guard sandbox.isPersistent, Self.isStale(exitCode: first.exitCode, output: first.output, in: sandbox)
        else { return first }

        for name in WarmSandboxes.keptDirectories {
            try? FileManager.default.removeItem(at: sandbox.rootURL.appendingPathComponent(name))
        }
        return try await launcher.launchCapturing(request)
    }

    static func isStale(exitCode: Int32, output: String, in sandbox: Sandbox) -> Bool {
        guard exitCode != 0, exitCode != SPMResultParser.timedOutExitCode else { return false }
        let root = CanonicalPath.make(for: sandbox.rootURL.path)
        return SchemaNarrower.errorLocations(in: output, under: root).isEmpty
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
