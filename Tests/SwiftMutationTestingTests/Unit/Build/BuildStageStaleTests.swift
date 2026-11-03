import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BuildStage — stale warm sandbox")
struct BuildStageStaleTests {

    @Test("Given a kept sandbox whose build fails naming none of its files, when run, then it is built once more cold")
    func retriesColdWhenNothingInTheSandboxIsBlamed() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sandbox = try persistentSandbox(in: dir)
        let launcher = RecordingProcessLauncher(responses: [
            (exitCode: 1, output: "error: module 'App' was built with a different version of the compiler"),
            (exitCode: 0, output: "Build complete!"),
        ])

        let result = try await BuildStage(launcher: launcher).run(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: 5), in: sandbox
        )

        #expect(result.exitCode == 0)
        #expect(await launcher.requests.count == 2)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(".build").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(".xmr-derived-data").path))
    }

    @Test("Given a kept sandbox whose build fails on one of its files, when run, then it is not retried")
    func keepsTheBuildWhenAFileOfTheSandboxIsBlamed() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sandbox = try persistentSandbox(in: dir)
        let root = CanonicalPath.make(for: dir.path)
        let launcher = RecordingProcessLauncher(responses: [
            (exitCode: 1, output: "\(root)/Sources/App/A.swift:3:5: error: cannot find 'x' in scope"),
            (exitCode: 0, output: ""),
        ])

        let result = try await BuildStage(launcher: launcher).run(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: 5), in: sandbox
        )

        #expect(result.exitCode == 1)
        #expect(await launcher.requests.count == 1)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".build/marker").path))
    }

    @Test("Given a throwaway sandbox whose build fails without blame, when run, then it is not retried")
    func anEphemeralSandboxIsNotRetried() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sandbox = Sandbox(rootURL: dir)
        let launcher = RecordingProcessLauncher(responses: [(exitCode: 1, output: "error: link failed"), (0, "")])

        let result = try await BuildStage(launcher: launcher).run(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: 5), in: sandbox
        )

        #expect(result.exitCode == 1)
        #expect(await launcher.requests.count == 1)
    }

    @Test("Given a kept sandbox whose build is killed by its timeout, when run, then it is not retried")
    func aTimedOutBuildIsNotRetried() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sandbox = try persistentSandbox(in: dir)
        let launcher = RecordingProcessLauncher(responses: [
            (exitCode: SPMResultParser.timedOutExitCode, output: ""), (0, ""),
        ])

        let result = try await BuildStage(launcher: launcher).run(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: 5), in: sandbox
        )

        #expect(result.exitCode == SPMResultParser.timedOutExitCode)
        #expect(await launcher.requests.count == 1)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".build/marker").path))
    }

    @Test("Given a kept sandbox built only by the cold retry, when buildSPM called, then it returns the artifact")
    func buildSPMReturnsTheArtifactAfterTheRetry() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sandbox = try persistentSandbox(in: dir)
        let launcher = RecordingProcessLauncher(responses: [
            (exitCode: 1, output: "error: could not build module 'Swift'"), (exitCode: 0, output: ""),
        ])

        let artifact = try await BuildStage(launcher: launcher).buildSPM(sandbox: sandbox, timeout: 5)

        #expect(artifact.derivedDataPath == dir.appendingPathComponent(".build").path)
        #expect(await launcher.requests.count == 2)
    }

    // MARK: - Private

    private func persistentSandbox(in dir: URL) throws -> Sandbox {
        for path in [".build/marker", ".xmr-derived-data/marker"] {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "built".write(to: url, atomically: true, encoding: .utf8)
        }
        return Sandbox(rootURL: dir, slot: WarmSandboxes.Slot(index: 0, lockDescriptor: -1))
    }
}
