import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BuildStage")
struct BuildStageTests {
    @Test("Given successful build and xctestrun present, when build called, then returns BuildArtifact")
    func returnsArtifactOnSuccess() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["__xctestrun_metadata__": ["FormatVersion": 1]],
            format: .xml,
            options: 0
        )
        try plistData.write(to: productsDir.appendingPathComponent("App.xctestrun"))

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        let artifact = try await stage.build(
            sandbox: sandbox,
            scheme: "App",
            destination: "platform=macOS,arch=arm64",
            timeout: 60
        )

        #expect(artifact.derivedDataPath == projectDir.appendingPathComponent(".xmr-derived-data").path)
        #expect(artifact.xctestrunURL.lastPathComponent == "App.xctestrun")
    }

    @Test("Given build failure, when build called, then throws compilationFailed")
    func throwsCompilationFailedOnNonZeroExitCode() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 1))

        await #expect(throws: BuildError.compilationFailed) {
            try await stage.build(
                sandbox: sandbox,
                scheme: "App",
                destination: "platform=macOS,arch=arm64",
                timeout: 60
            )
        }
    }

    @Test("Given successful build but missing xctestrun, when build called, then throws xctestrunNotFound")
    func throwsXctestrunNotFoundWhenFileAbsent() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let productsDir = projectDir.appendingPathComponent(".xmr-derived-data/Build/Products")
        try FileManager.default.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let sandbox = Sandbox(rootURL: projectDir)
        let stage = BuildStage(launcher: MockProcessLauncher(exitCode: 0))

        await #expect(throws: BuildError.xctestrunNotFound) {
            try await stage.build(
                sandbox: sandbox,
                scheme: "App",
                destination: "platform=macOS,arch=arm64",
                timeout: 60
            )
        }
    }
}
