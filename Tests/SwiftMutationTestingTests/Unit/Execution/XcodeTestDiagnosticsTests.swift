import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Xcode test runs — diagnostics")
struct XcodeTestDiagnosticsTests {
    @Test("Given a schematized mutant on Xcode, when its tests run, then xcodebuild is told not to collect diagnostics")
    func theTestPassCollectsNoDiagnostics() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool(launcher: launcher)
        try await pool.setUp()
        let plistDict: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))
        let stage = TestExecutionStage(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path)
        )
        let context = TestExecutionContext(
            artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: plist),
            sandbox: Sandbox(rootURL: dir),
            pool: pool,
            configuration: makeRunnerConfiguration()
        )

        _ = try await stage.execute(mutants: [makeMutantDescriptor(isSchematizable: true)], in: context)

        let tests = await launcher.requests.filter { $0.arguments.first == "test-without-building" }
        #expect(!tests.isEmpty)
        #expect(tests.allSatisfy { $0.arguments.joined(separator: " ").contains("-collect-test-diagnostics never") })
    }
}
