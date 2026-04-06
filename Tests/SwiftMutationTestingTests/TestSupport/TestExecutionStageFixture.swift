import Foundation

@testable import SwiftMutationTesting

func makeTestExecutionFixture(
    in dir: URL,
    exitCode: Int32,
    output: String = ""
) -> (TestExecutionStage, TestExecutionContext) {
    let launcher = MockProcessLauncher(exitCode: exitCode, output: output)
    let pool = makeSimulatorPool(launcher: launcher)
    let stage = TestExecutionStage(
        deps: makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path,
            total: 3
        )
    )
    let context = TestExecutionContext(
        artifact: makeBuildArtifact(in: dir),
        sandbox: Sandbox(rootURL: dir),
        pool: pool,
        configuration: makeRunnerConfiguration()
    )
    return (stage, context)
}

func makeTestExecutionSPMFixture(
    in dir: URL,
    exitCode: Int32,
    output: String = ""
) -> (TestExecutionStage, TestExecutionContext) {
    let launcher = MockProcessLauncher(exitCode: exitCode, output: output)
    let pool = makeSimulatorPool(launcher: launcher)
    let stage = TestExecutionStage(
        deps: makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )
    )
    let config = makeRunnerConfiguration(projectType: .spm)
    let context = TestExecutionContext(
        artifact: BuildArtifact(derivedDataPath: dir.path, xctestrunURL: nil, plist: nil),
        sandbox: Sandbox(rootURL: dir),
        pool: pool,
        configuration: config
    )
    return (stage, context)
}
