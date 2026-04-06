@testable import SwiftMutationTesting

func makeRunnerConfiguration(
    projectPath: String = "/tmp",
    projectType: ProjectType = .xcode(scheme: "MyScheme", destination: "platform=macOS"),
    testTarget: String? = nil,
    timeout: Double = 60,
    concurrency: Int = 1,
    noCache: Bool = false,
    output: String? = nil,
    htmlOutput: String? = nil,
    sonarOutput: String? = nil,
    quiet: Bool = true,
    excludePatterns: [String] = [],
    operators: [String] = []
) -> RunnerConfiguration {
    RunnerConfiguration(
        projectPath: projectPath,
        build: .init(
            projectType: projectType,
            testTarget: testTarget,
            timeout: timeout,
            concurrency: concurrency,
            noCache: noCache
        ),
        reporting: .init(
            output: output,
            htmlOutput: htmlOutput,
            sonarOutput: sonarOutput,
            quiet: quiet
        ),
        filter: .init(excludePatterns: excludePatterns, operators: operators)
    )
}
