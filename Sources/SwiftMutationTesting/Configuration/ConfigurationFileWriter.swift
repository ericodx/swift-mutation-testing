import Foundation

struct ConfigurationFileWriter: Sendable {
    func write(to projectPath: String, project: DetectedProject) throws {
        let fileURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".swift-mutation-testing.yml")

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UsageError(message: ".swift-mutation-testing.yml already exists at \(fileURL.path)")
        }

        try generateContent(project: project).write(to: fileURL, atomically: true, encoding: .utf8)
        print("Created \(fileURL.path)")
    }

    private func generateContent(project: DetectedProject) -> String {
        var lines: [String] = []

        lines.append("# swift-mutation-testing configuration")
        lines.append("# All settings are optional. CLI flags override file values.")
        lines.append("")

        if project.allSchemes.count > 1 {
            lines.append("# Available schemes: \(project.allSchemes.joined(separator: ", "))")
        }

        lines.append("# Xcode-only: required when testRunner is xcodebuild")
        lines.append("testRunner: xcodebuild")

        if let scheme = project.scheme {
            lines.append("scheme: \(scheme)")
        } else {
            lines.append("# scheme: MyApp")
        }

        lines.append("destination: \(project.destination)")
        lines.append("")

        if let testTarget = project.testTarget {
            lines.append("# Limit test execution to a specific target (recommended when the project has UI tests)")
            lines.append("testTarget: \(testTarget)")
        } else {
            lines.append("# Limit test execution to a specific target (recommended when the project has UI tests)")
            lines.append("# testTarget: MyAppTests")
        }

        lines.append("")
        lines.append("# Per-mutant test timeout in seconds (default: 60)")
        lines.append("timeout: 60")
        lines.append("")
        lines.append("# Parallel simulators (4 recommended for Xcode)")
        lines.append("concurrency: 4")
        lines.append("")
        lines.append("# Report output paths")
        lines.append("# output: mutation-report.json")
        lines.append("# htmlOutput: mutation-report.html")
        lines.append("# sonarOutput: sonar-report.json")
        lines.append("")
        lines.append("# Source file glob patterns to exclude from mutation")

        if let testTarget = project.testTarget {
            lines.append("exclude:")
            lines.append("  - \"/\(testTarget)/\"")
        } else {
            lines.append("# exclude:")
            lines.append("#   - \"**/Generated/**\"")
        }

        lines.append(contentsOf: mutatorsSection())

        return lines.joined(separator: "\n") + "\n"
    }

    private func mutatorsSection() -> [String] {
        var lines = ["", "# Mutation operators — set active: false to disable", "mutators:"]
        for name in DiscoveryPipeline.allOperatorNames {
            lines.append("  - name: \(name)")
            lines.append("    active: true")
        }
        return lines
    }
}
