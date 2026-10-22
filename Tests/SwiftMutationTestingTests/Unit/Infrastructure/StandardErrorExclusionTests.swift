import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Standard error kept out of parsed JSON")
struct StandardErrorExclusionTests {

    @Test("Given a process that writes to both streams, when captured, then both are in the output")
    func standardErrorIsCapturedByDefault() async throws {
        let result = try await ProcessRunner(onTimeout: { _ in }).launchCapturing(Self.bothStreams)

        #expect(result.output.contains("{\"out\": 1}"))
        #expect(result.output.contains("warning: on stderr"))
    }

    @Test("Given a request that discards standard error, when captured, then the output is stdout alone")
    func standardErrorIsDiscardedWhenAsked() async throws {
        let result = try await ProcessRunner(onTimeout: { _ in })
            .launchCapturing(Self.bothStreams.discardingStandardError())

        #expect(result.output == "{\"out\": 1}\n")
    }

    @Test("Given an iOS project, when detected, then xcodebuild -list and simctl are read without stderr")
    func detectionOfAnXcodeProjectDiscardsStandardError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let project = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: project.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8
        )
        let launcher = CountingLauncher(
            wrapping: MockProcessLauncher(
                exitCode: 0, output: Self.projectList, responses: ["xcrun": (exitCode: 0, output: Self.devices)]
            )
        )

        _ = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        let parsed = await launcher.requests.filter {
            $0.arguments.contains("-list") || $0.arguments.starts(with: ["simctl", "list"])
        }
        #expect(parsed.contains { $0.arguments.contains("-list") })
        #expect(parsed.contains { $0.arguments.starts(with: ["simctl", "list"]) })
        #expect(parsed.allSatisfy { $0.discardsStandardError })
    }

    @Test("Given a package, when detected, then dump-package is read without stderr")
    func detectionOfAPackageDiscardsStandardError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "// swift-tools-version: 6.0".write(
            to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0, output: Self.packageDump))

        _ = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        let dump = try #require(await launcher.requests.first { $0.arguments.contains("dump-package") })
        #expect(dump.discardsStandardError)
    }

    @Test("Given a failed Xcode run, when parsed, then xcresulttool is read without stderr")
    func xcresulttoolDiscardsStandardError() async throws {
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 1))

        _ = try await ResultParser(launcher: launcher).parse(
            exitCode: 1, output: "", xcresultPath: "/tmp/test.xcresult", timeout: 60
        )

        let request = try #require(await launcher.requests.first { $0.arguments.contains("xcresulttool") })
        #expect(request.discardsStandardError)
    }

    @Test("Given simulators to clone and boot, when set up, then every simctl list is read without stderr")
    func simulatorListsDiscardStandardError() async throws {
        let launcher = CountingLauncher(
            wrapping: SimulatorCommandMock(
                listOutput: SimulatorCommandMock.bootedDevicesJSON(udid: "CLONE"), cloneUDID: "CLONE"
            )
        )
        let pool = SimulatorPool(
            baseUDID: "BASE", size: 1, destination: "platform=iOS Simulator,name=iPhone 15", launcher: launcher
        )

        try await pool.setUp()
        try await SimulatorManager(launcher: launcher).waitForBooted(udid: "CLONE")

        let lists = await launcher.requests.filter { $0.arguments.starts(with: ["simctl", "list"]) }
        #expect(lists.count >= 2)
        #expect(lists.allSatisfy { $0.discardsStandardError })
    }

    // MARK: - Private

    private static let bothStreams = ProcessRequest(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo 'warning: on stderr' >&2; echo '{\"out\": 1}'"],
        environment: nil,
        additionalEnvironment: [:],
        workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
        timeout: 20
    )

    private static let projectList = """
        {"project": {"name": "MyApp", "schemes": ["MyApp"], "targets": ["MyApp", "MyAppTests"]}}
        """

    private static let devices = """
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-0": [{"name": "iPhone 16 Pro", "isAvailable": true}]}}
        """

    private static let packageDump = """
        {"targets": [{"name": "PkgTests", "type": "test"}]}
        """
}
