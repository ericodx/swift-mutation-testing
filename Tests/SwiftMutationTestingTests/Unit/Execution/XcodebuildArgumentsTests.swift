import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Xcode runs — extra xcodebuild arguments")
struct XcodebuildArgumentsTests {
    private let extra = ["-allowProvisioningUpdates", "OTHER_SWIFT_FLAGS=-DMUTATING"]

    @Test("Given a container and extra arguments, when the Xcode arguments are read, then the extra ones come last")
    func extraArgumentsFollowTheContainer() {
        var configuration = makeRunnerConfiguration(xcodebuildArguments: extra)
        configuration.build.xcodeContainer = .workspace("App.xcworkspace")

        #expect(configuration.build.xcodeArguments == ["-workspace", "App.xcworkspace"] + extra)
    }

    @Test("Given extra arguments, when the shared build runs, then build-for-testing ends with them")
    func theSharedBuildGetsTheExtraArguments() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let launcher = RecordingProcessLauncher(responses: [(0, "")])

        _ = try? await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, xcodebuildArguments: extra),
            launcher: launcher
        ).execute(
            makeRunnerInput(
                projectPath: dir.path,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        let build = try #require(await launcher.recorded(commandStartingWith: "build-for-testing"))
        #expect(build.arguments.suffix(2) == extra[...])
    }

    @Test("Given extra arguments, when a schematized mutant's tests run, then test-without-building ends with them")
    func theTestPassGetsTheExtraArguments() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool(launcher: launcher)
        try await pool.setUp()
        let plistDict: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: plist),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeRunnerConfiguration(xcodebuildArguments: extra)
        )

        _ = try await TestExecutionStage(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path)
        ).execute(mutants: [makeMutantDescriptor(isSchematizable: true)], in: context)

        let tests = await launcher.requests.filter { $0.arguments.first == "test-without-building" }
        #expect(!tests.isEmpty)
        #expect(tests.allSatisfy { $0.arguments.suffix(2) == extra[...] })
    }

    @Test("Given extra arguments, when an incompatible mutant is built and tested, then both calls end with them")
    func incompatibleCallsGetTheExtraArguments() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = 1".write(to: sourceFile, atomically: true, encoding: .utf8)
        let pool = makeSimulatorPool()
        try await pool.setUp()
        let launcher = RecordingProcessLauncher(responses: [(0, ""), (0, "")])
        let mutant = makeMutantDescriptor(
            id: "m0", filePath: sourceFile.path, originalText: "1", mutatedText: "2",
            operatorIdentifier: "ArithmeticOperatorReplacement", description: "1 → 2", isSchematizable: false,
            mutatedSourceContent: "let x = 2"
        )

        _ = try await IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("cache.json").path),
            sandboxFactory: SandboxFactory()
        ).execute(
            [mutant], configuration: makeRunnerConfiguration(projectPath: dir.path, xcodebuildArguments: extra),
            pool: pool
        )

        let build = try #require(await launcher.recorded(commandStartingWith: "build-for-testing"))
        let test = try #require(await launcher.recorded(commandStartingWith: "test-without-building"))
        #expect(build.arguments.suffix(2) == extra[...])
        #expect(test.arguments.suffix(2) == extra[...])
    }
}
