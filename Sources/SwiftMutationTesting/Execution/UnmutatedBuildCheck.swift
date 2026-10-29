import Foundation

struct UnmutatedBuildCheck: Sendable {
    let configuration: RunnerConfiguration
    let stage: BuildStage

    func verify(in sandbox: Sandbox) async throws {
        do {
            try await build(sandbox)
        } catch BuildError.compilationFailed(let output) {
            MutantLogWriter(directory: configuration.reporting.keepLogsPath)?.write(baselineOutput: output)
            throw BaselineError.buildFailed(output: output)
        } catch BuildError.xctestrunNotFound {
            return
        }
    }

    private func build(_ sandbox: Sandbox) async throws {
        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            _ = try await stage.build(
                sandbox: sandbox,
                arguments: configuration.build.xcodeArguments,
                scheme: scheme,
                destination: destination,
                timeout: configuration.build.buildTimeout
            )

        case .spm:
            _ = try await stage.buildSPM(sandbox: sandbox, timeout: configuration.build.buildTimeout)
        }
    }
}
