import Foundation

struct UnmutatedSuiteCheck: Sendable {
    let configuration: RunnerConfiguration
    let deps: ExecutionDeps

    func verify(in sandbox: Sandbox, pool: SimulatorPool) async throws {
        let stage = BuildStage(launcher: deps.launcher)
        let artifact: BuildArtifact
        do {
            artifact = try await build(sandbox, stage: stage)
        } catch BuildError.compilationFailed(let output) {
            MutantLogWriter(directory: configuration.reporting.keepLogsPath)?.write(baselineOutput: output)
            throw BaselineError.buildFailed(output: output)
        }

        switch configuration.build.projectType {
        case .spm:
            _ = try await BaselineProbe(configuration: configuration, launcher: deps.launcher)
                .probeTestBundles(in: sandbox)

        case .xcode:
            let context = TestExecutionContext(
                artifact: artifact, sandbox: sandbox, pool: pool, configuration: configuration,
                testFilter: configuration.build.testTarget
            )
            try await TestExecutionStage(deps: deps).requireXcodeBaselineToPass(in: context)
        }
    }

    // MARK: - Private

    private func build(_ sandbox: Sandbox, stage: BuildStage) async throws -> BuildArtifact {
        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            try await stage.build(
                sandbox: sandbox,
                arguments: configuration.build.xcodeArguments,
                scheme: scheme,
                destination: destination,
                timeout: configuration.build.buildTimeout
            )

        case .spm:
            try await stage.buildSPM(sandbox: sandbox, timeout: configuration.build.buildTimeout)
        }
    }
}
