import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor — the simulator pool during the build")
struct MutantExecutorPoolTests {

    @Test("Given a simulator destination, when executed, then the clones are made and booted while the schema builds")
    func thePoolIsSetUpDuringTheBuild() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let launcher = PoolTimingLauncher(buildExitCode: 0)

        let results = try await MutantExecutor(configuration: Self.configuration(in: dir), launcher: launcher)
            .execute(Self.input(in: dir, sourceFile: sourceFile))

        #expect(results.count == 1)
        let build = try #require(await launcher.first("build-for-testing"))
        let boots = await launcher.calls.filter { $0.arguments.starts(with: ["simctl", "boot"]) }
        #expect(boots.count == 2)
        #expect(boots.allSatisfy { $0.ended < build.ended }, "every clone was booted before the build ended")
        let listed = try #require(await launcher.first("simctl"))
        #expect(listed.started < build.ended)
    }

    @Test("Given the project does not build, when executed, then the pool set up meanwhile is torn down")
    func aFailedBuildTearsDownThePool() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let launcher = PoolTimingLauncher(buildExitCode: 1)

        await #expect(throws: BaselineError.buildFailed(output: "Validate plug-in")) {
            try await MutantExecutor(configuration: Self.configuration(in: dir), launcher: launcher)
                .execute(Self.input(in: dir, sourceFile: sourceFile))
        }

        let deletes = await launcher.calls.filter { $0.arguments.starts(with: ["simctl", "delete"]) }
        #expect(deletes.map(\.arguments.last) == ["CLONE-UDID", "CLONE-UDID"])
        let builds = await launcher.calls.filter { $0.arguments.first == "build-for-testing" }
        #expect(deletes.allSatisfy { delete in builds.allSatisfy { $0.ended <= delete.started } })
    }

    // MARK: - Private

    private static func configuration(in dir: URL) -> RunnerConfiguration {
        makeRunnerConfiguration(
            projectPath: dir.path,
            projectType: .xcode(scheme: "App", destination: "platform=iOS Simulator,name=iPhone 15"),
            concurrency: 2
        )
    }

    private static func input(in dir: URL, sourceFile: URL) -> RunnerInput {
        makeRunnerInput(
            projectPath: dir.path,
            projectType: .xcode(scheme: "App", destination: "platform=iOS Simulator,name=iPhone 15"),
            concurrency: 2,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
        )
    }
}

private actor PoolTimingLauncher: ProcessLaunching {
    struct Call: Sendable {
        let arguments: [String]
        let started: Date
        let ended: Date
    }

    init(buildExitCode: Int32) {
        self.buildExitCode = buildExitCode
    }

    private let buildExitCode: Int32
    private(set) var calls: [Call] = []

    private static let listJSON = """
        {"devices":{"com.apple.runtime.iOS":[
            {"udid":"BASE-UDID","name":"iPhone 15","state":"Booted"},
            {"udid":"CLONE-UDID","name":"Clone","state":"Booted"}
        ]}}
        """

    func first(_ verb: String) -> Call? {
        calls.first { $0.arguments.first == verb }
    }

    func launch(
        executableURL: URL, arguments: [String], workingDirectoryURL: URL, timeout: Double
    ) async throws -> Int32 {
        record(arguments, started: Date())
        return 0
    }

    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()
        let started = Date()
        defer { record(request.arguments, started: started) }

        switch request.arguments.first {
        case "build-for-testing":
            try await Task.sleep(for: .milliseconds(300))
            guard buildExitCode == 0 else { return (buildExitCode, "Validate plug-in") }
            writeXctestrun(for: request)
            return (0, "")

        case "simctl" where request.arguments.contains("clone"):
            return (0, "CLONE-UDID\n")

        case "simctl":
            return (0, Self.listJSON)

        case "xcresulttool":
            return (1, "")

        default:
            return (0, "")
        }
    }

    private func record(_ arguments: [String], started: Date) {
        calls.append(Call(arguments: arguments, started: started, ended: Date()))
    }

    private func writeXctestrun(for request: ProcessRequest) {
        guard let index = request.arguments.firstIndex(of: "-derivedDataPath"), index + 1 < request.arguments.count
        else { return }

        let products = URL(fileURLWithPath: request.arguments[index + 1]).appendingPathComponent("Build/Products")
        try? FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let plist: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: products.appendingPathComponent("App.xctestrun"))
    }
}
