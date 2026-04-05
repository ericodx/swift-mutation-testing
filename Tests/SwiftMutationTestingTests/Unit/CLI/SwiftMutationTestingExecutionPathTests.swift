import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SwiftMutationTesting.run execution path")
struct SwiftMutationTestingExecutionPathTests {
    @Test("Given valid config with macOS destination and no Swift files, when run called, then returns success")
    func mainExecutionPathWithEmptyProjectReturnsSuccess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .success)
    }

    @Test("Given valid config with quiet false and no Swift files, when run called, then returns success")
    func quietFalseExecutionPathReturnsSuccess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\nquiet: false\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .success)
    }

    @Test("Given iOS Simulator destination with invalid simctl output, when run called, then returns error")
    func iOSSimulatorDestinationWithInvalidSimctlOutputReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: \"platform=iOS Simulator,name=iPhone 15\"\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1, output: "not-valid-json")
        )

        #expect(result == .error)
    }

    @Test("Given iOS Simulator destination with valid simctl output, when run called, then SimulatorPool is created")
    func iOSSimulatorPoolIsCreatedWhenDestinationRequiresSimulator() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cloneUDID = "CLONE-UDID"
        let listJSON = """
            {"devices":{"com.apple.runtime.iOS":[
                {"udid":"BASE-UDID","name":"iPhone 15","state":"Booted"},
                {"udid":"\(cloneUDID)","name":"Clone","state":"Booted"}
            ]}}
            """
        let yml = "scheme: NonExistentScheme\ndestination: \"platform=iOS Simulator,name=iPhone 15\"\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: IOSSimulatorMock(listJSON: listJSON, cloneUDID: cloneUDID)
        )

        #expect(result == .success)
    }

    @Test("Given xcode project type, when defaultLauncher called, then returns XcodeProcessLauncher")
    func defaultLauncherForXcodeReturnsXcodeProcessLauncher() {
        let launcher = SwiftMutationTesting.defaultLauncher(for: .xcode(scheme: "S", destination: "d"))
        #expect(launcher is XcodeProcessLauncher)
    }

    @Test("Given spm project type, when defaultLauncher called, then returns SPMProcessLauncher")
    func defaultLauncherForSPMReturnsSPMProcessLauncher() {
        let launcher = SwiftMutationTesting.defaultLauncher(for: .spm)
        #expect(launcher is SPMProcessLauncher)
    }

    @Test("Given corrupted cache file at project path, when run called, then returns error")
    func corruptedCacheFileReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let cacheDir = dir.appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try "not valid json at all!!!".write(
            to: cacheDir.appendingPathComponent("results.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .error)
    }
}
