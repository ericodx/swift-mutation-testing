import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SwiftMutationTesting.run execution path")
struct SwiftMutationTestingExecutionPathTests {
    @Test(
        "Given valid config with macOS destination and no Swift files, when run called, then it fails: nothing was measured"
    )
    func mainExecutionPathWithEmptyProjectFails() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .error)
    }

    @Test("Given valid config with quiet false and no Swift files, when run called, then it fails with no score")
    func quietFalseExecutionPathWithEmptyProjectFails() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\nquiet: false\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .error)
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
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: UnmutatedBuildPassingLauncher(base: IOSSimulatorMock(listJSON: listJSON, cloneUDID: cloneUDID))
        )

        #expect(result == .success)
    }

    @Test("Given xcode project type, when defaultLauncher called, then returns XcodeProcessLauncher")
    func defaultLauncherForXcodeReturnsXcodeProcessLauncher() {
        let launcher = ProjectType.xcode(scheme: "S", destination: "d").defaultLauncher
        #expect(launcher is XcodeProcessLauncher)
    }

    @Test("Given spm project type, when defaultLauncher called, then returns SPMProcessLauncher")
    func defaultLauncherForSPMReturnsSPMProcessLauncher() {
        let launcher = ProjectType.spm.defaultLauncher
        #expect(launcher is SPMProcessLauncher)
    }

    @Test("Given corrupted cache file at project path, when run called, then the run goes on without it")
    func corruptedCacheFileIsIgnored() async throws {
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
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1))
        )

        #expect(result == .success)
    }

    @Test("Given a project that does not build, when run called, then it fails without a score")
    func unbuildableProjectFailsWithoutAScore() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try "scheme: App\ndestination: platform=macOS\n".write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8
        )
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )

        var result: ExitCode = .success
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(args: [dir.path], launcher: MockProcessLauncher(exitCode: 1))
        }

        #expect(result == .error)
        #expect(!output.contains("mutation score"))
    }

    @Test("Given quiet is off and the project has mutants, when run called, then discovery is reported")
    func quietFalseReportsWhatDiscoveryFound() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\nquiet: false\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )

        var result: ExitCode = .error
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(
                args: [dir.path], launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1)))
        }

        #expect(result == .success)
        #expect(output.contains("Discovery"))
        #expect(output.contains("1 mutant"))
    }

    @Test("Given no launcher and no Swift files, when run called, then it stops before launching anything")
    func runWithoutALauncherAndNoMutantsStops() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(args: [dir.path])

        #expect(result == .error)
    }

    @Test("Given --sources-path naming one file, when run, then only that file's mutants run")
    func aSingleFileRuns() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "scheme: App\ndestination: platform=macOS\n".write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8
        )
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )
        try "func g(_ a: Bool, _ b: Bool) -> Bool { a || b }\n".write(
            to: dir.appendingPathComponent("Bar.swift"), atomically: true, encoding: .utf8
        )
        let reportPath = dir.appendingPathComponent("r.json").path

        let result = await SwiftMutationTesting.run(
            args: [
                dir.path, "--sources-path", dir.appendingPathComponent("Foo.swift").path, "--output", reportPath,
                "--quiet",
            ],
            launcher: UnmutatedBuildPassingLauncher(base: MockProcessLauncher(exitCode: 1))
        )

        #expect(result == .success)
        let report = try JSONDecoder().decode(
            MutationReportPayload.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath))
        )
        #expect(Array(report.files.keys) == ["/Foo.swift"])
    }

    @Test("Given a sources path where nothing is mutable, when run, then it fails with the reason and no report")
    func noMutantsIsAFailureNotAPerfectScore() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "scheme: App\ndestination: platform=macOS\n".write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8
        )
        try "let constant = 1\n".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        let reportPath = dir.appendingPathComponent("r.json").path
        let launcher = RecordingProcessLauncher(responses: [(0, "")])

        let result = await SwiftMutationTesting.run(args: [dir.path, "--output", reportPath], launcher: launcher)

        #expect(result == .error)
        #expect(await launcher.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reportPath))
        #expect(
            FileDiscoveryError.noMutants(sourcesPath: dir.path).localizedDescription
                .contains("nothing was measured and no score is given")
        )
    }

    @Test("Given nothing mutable, when plan runs, then no plan is written")
    func anEmptyPlanIsNotWritten() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try "scheme: App\ndestination: platform=macOS\n".write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8
        )
        let planPath = dir.appendingPathComponent("plan.json").path

        let result = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])

        #expect(result == .error)
        #expect(!FileManager.default.fileExists(atPath: planPath))
    }
}
