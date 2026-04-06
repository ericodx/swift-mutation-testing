@testable import SwiftMutationTesting

func makeDiscoveryInput(
    projectPath: String = "/project",
    projectType: ProjectType = .xcode(scheme: "Scheme", destination: "platform=macOS"),
    timeout: Double = 60,
    concurrency: Int = 4,
    noCache: Bool = false,
    sourcesPath: String,
    excludePatterns: [String] = [],
    operators: [String] = []
) -> DiscoveryInput {
    DiscoveryInput(
        projectPath: projectPath,
        projectType: projectType,
        timeout: timeout,
        concurrency: concurrency,
        noCache: noCache,
        sourcesPath: sourcesPath,
        excludePatterns: excludePatterns,
        operators: operators
    )
}
