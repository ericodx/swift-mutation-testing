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
        switch project.kind {
        case .xcode(let scheme, let allSchemes, let destination):
            return generateXcodeContent(
                scheme: scheme,
                allSchemes: allSchemes,
                destination: destination,
                testTarget: project.testTarget
            )
        case .spm(let testTargets):
            return generateSPMContent(testTargets: testTargets, testTarget: project.testTarget)
        }
    }

    private func generateXcodeContent(
        scheme: String?,
        allSchemes: [String],
        destination: String,
        testTarget: String?
    ) -> String {
        var lines: [String] = []

        lines.append("# swift-mutation-testing configuration")
        lines.append("# All settings are optional. CLI flags override file values.")
        lines.append("")

        if allSchemes.count > 1 {
            lines.append("# Available schemes: \(allSchemes.joined(separator: ", "))")
        }

        if let scheme {
            lines.append("scheme: \(scheme)")
        } else {
            lines.append("# scheme: MyApp")
        }

        lines.append("destination: \(destination)")
        lines.append("")

        if let testTarget {
            lines.append("# Limit test execution to a specific target (recommended when the project has UI tests)")
            lines.append("testTarget: \(testTarget)")
        } else {
            lines.append("# Limit test execution to a specific target (recommended when the project has UI tests)")
            lines.append("# testTarget: MyAppTests")
        }

        lines.append("")
        lines.append("# Per-mutant test timeout in seconds (default: 120)")
        lines.append("timeout: 120")
        lines.append("")
        lines.append("# Number of parallel workers (default: max(1, CPU count - 1))")
        lines.append("concurrency: 4")
        lines.append("")
        lines.append("# Disable result cache (re-runs all mutants on every execution)")
        lines.append("# noCache: true")
        lines.append("")
        lines.append("# Report output paths")
        lines.append("# output: mutation-report.json")
        lines.append("# htmlOutput: mutation-report.html")
        lines.append("sonarOutput: sonar-mutation-report.json")
        lines.append("")
        lines.append("# Source file glob patterns to exclude from mutation")

        if let testTarget {
            lines.append("exclude:")
            lines.append("  - \"/\(testTarget)/\"")
        } else {
            lines.append("# exclude:")
            lines.append("#   - \"**/Generated/**\"")
        }

        lines.append(contentsOf: mutatorsSection())

        return lines.joined(separator: "\n") + "\n"
    }

    private func generateSPMContent(testTargets: [String], testTarget: String?) -> String {
        var lines: [String] = []

        lines.append("# swift-mutation-testing configuration")
        lines.append("# All settings are optional. CLI flags override file values.")
        lines.append("")

        if testTargets.count > 1 {
            lines.append("# Available test targets: \(testTargets.joined(separator: ", "))")
        }

        if let testTarget {
            lines.append("# Limit test execution to a specific target")
            lines.append("testTarget: \(testTarget)")
        } else {
            lines.append("# Limit test execution to a specific target")
            lines.append("# testTarget: MyPackageTests")
        }

        lines.append("")
        lines.append("# Per-mutant test timeout in seconds (default: 120)")
        lines.append("timeout: 120")
        lines.append("")
        lines.append("# Disable result cache (re-runs all mutants on every execution)")
        lines.append("# noCache: true")
        lines.append("")
        lines.append("# Report output paths")
        lines.append("# output: mutation-report.json")
        lines.append("# htmlOutput: mutation-report.html")
        lines.append("sonarOutput: sonar-mutation-report.json")
        lines.append("")
        lines.append("# Source file glob patterns to exclude from mutation")

        if let testTarget {
            lines.append("exclude:")
            lines.append("  - \"/\(testTarget)/\"")
        } else {
            lines.append("# exclude:")
            lines.append("#   - \"**/Tests/**\"")
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
