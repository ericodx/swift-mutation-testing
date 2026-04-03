import Foundation

struct TestResultResolver: Sendable {
    let launcher: any ProcessLaunching

    func resolve(
        launch: TestLaunchResult,
        projectType: ProjectType,
        timeout: TimeInterval
    ) async throws -> TestRunOutcome {
        switch projectType {
        case .xcode:
            return try await ResultParser(launcher: launcher).parse(
                exitCode: launch.exitCode,
                output: launch.output,
                xcresultPath: launch.xcresultPath,
                timeout: timeout
            )

        case .spm:
            return SPMResultParser().parse(exitCode: launch.exitCode, output: launch.output)
        }
    }
}
