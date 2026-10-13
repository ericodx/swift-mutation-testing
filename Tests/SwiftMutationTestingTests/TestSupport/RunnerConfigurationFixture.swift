@testable import SwiftMutationTesting

func makeRunnerConfiguration(
    projectPath: String = "/tmp",
    projectType: ProjectType = .xcode(scheme: "MyScheme", destination: "platform=macOS"),
    testTarget: String? = nil,
    xcodebuildArguments: [String] = [],
    timeout: Double = 60,
    buildTimeout: Double = 60,
    concurrency: Int = 1,
    noCache: Bool = false,
    output: String? = nil,
    htmlOutput: String? = nil,
    sonarOutput: String? = nil,
    sarifOutput: String? = nil,
    markdownOutput: String? = nil,
    keepLogsPath: String? = nil,
    quiet: Bool = true,
    excludePatterns: [String] = [],
    operators: [String] = []
) -> RunnerConfiguration {
    RunnerConfiguration(
        projectPath: projectPath,
        build: .init(
            projectType: projectType,
            xcodebuildArguments: xcodebuildArguments,
            testTarget: testTarget,
            timeout: timeout,
            buildTimeout: buildTimeout,
            concurrency: concurrency,
            noCache: noCache
        ),
        reporting: .init(
            outputs: [
                .json: output, .html: htmlOutput, .sonar: sonarOutput, .sarif: sarifOutput, .markdown: markdownOutput,
            ].compactMapValues { $0 },
            keepLogsPath: keepLogsPath,
            quiet: quiet
        ),
        filter: .init(excludePatterns: excludePatterns, operators: operators)
    )
}
