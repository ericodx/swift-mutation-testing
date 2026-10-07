import Foundation

struct ConfigurationFileWriter: Sendable {
    func write(to projectPath: String, project: DetectedProject) throws {
        let fileURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".swift-mutation-testing.yml")

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UsageError(message: ".swift-mutation-testing.yml already exists at \(fileURL.path)")
        }

        try generateContent(project: project).write(to: fileURL, atomically: true, encoding: .utf8)
        StandardOutput.write("Created \(fileURL.path)")
    }

    private func generateContent(project: DetectedProject) -> String {
        switch project.kind {
        case .xcode(let scheme, let allSchemes, let destination):
            return generateXcodeContent(
                project: project, scheme: scheme, allSchemes: allSchemes, destination: destination
            )
        case .spm(let testTargets):
            return generateSPMContent(testTargets: testTargets, testTarget: project.testTarget)
        }
    }

    private func generateXcodeContent(
        project: DetectedProject,
        scheme: String?,
        allSchemes: [String],
        destination: String
    ) -> String {
        let testTarget = project.testTarget
        let testingFramework = project.testingFramework
        var lines: [String] = []

        lines.append("# swift-mutation-testing configuration")
        lines.append("# All settings are optional. CLI flags override file values.")
        lines.append("")
        lines.append(contentsOf: containerLines(project))

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
        lines.append("# Testing framework: xctest or swift-testing (default: swift-testing)")
        lines.append("# When xctest is selected, concurrency is forced to 1 for deterministic results")
        lines.append("testing-framework: \(testingFramework.rawValue)")
        lines.append("")

        if let testTarget {
            lines.append("# Limit test execution to a specific target (recommended when the project has UI tests)")
            lines.append("test-target: \(testTarget)")
        } else {
            lines.append("# Limit test execution to a specific target (recommended when the project has UI tests)")
            lines.append("# test-target: MyAppTests")
        }

        lines.append(contentsOf: xcodeRunSection(testingFramework: testingFramework, testTarget: testTarget))

        return lines.joined(separator: "\n") + "\n"
    }

    private func containerLines(_ project: DetectedProject) -> [String] {
        if let container = project.xcodeContainer {
            return ["\(container.key): \(container.path)", ""]
        }
        guard let note = project.containerNote else { return [] }
        return ["# No workspace or project was chosen: \(note)", "# Uncomment the one to build:"]
            + project.containerCandidates.map { "# \($0.key): \($0.path)" } + [""]
    }

    private func xcodeRunSection(testingFramework: TestingFramework, testTarget: String?) -> [String] {
        var lines: [String] = []
        lines.append("")
        lines.append("# Per-mutant test timeout in seconds (default: 120)")
        lines.append("timeout: 120")
        lines.append("")
        lines.append("# Build timeout in seconds (default: 120)")
        lines.append("# build-timeout: 240")
        lines.append("")
        lines.append("# Number of parallel workers (default: max(1, CPU count - 1))")
        if testingFramework == .xctest {
            lines.append("concurrency: 1")
        } else {
            lines.append("concurrency: 4")
        }
        lines.append(contentsOf: reportSection(testTarget: testTarget, excludeExample: "**/Generated/**"))
        lines.append(contentsOf: gateSection())
        lines.append(contentsOf: mutatorsSection())
        return lines
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
            lines.append("test-target: \(testTarget)")
        } else {
            lines.append("# Limit test execution to a specific target")
            lines.append("# test-target: MyPackageTests")
        }

        lines.append("")
        lines.append("# Per-mutant test timeout in seconds (default: 30 for SPM)")
        lines.append("timeout: 30")
        lines.append("")
        lines.append("# Build timeout in seconds (default: 120)")
        lines.append("# build-timeout: 240")
        lines.append(contentsOf: reportSection(testTarget: testTarget, excludeExample: "**/Tests/**"))
        lines.append(contentsOf: gateSection())
        lines.append(contentsOf: mutatorsSection())

        return lines.joined(separator: "\n") + "\n"
    }

    private func reportSection(testTarget: String?, excludeExample: String) -> [String] {
        var lines: [String] = []
        lines.append("")
        lines.append("# Disable result cache (re-runs all mutants on every execution)")
        lines.append("# no-cache: true")
        lines.append("")
        lines.append("# Report output paths")
        for format in ReportFormat.allCases {
            lines.append("\(format == .json ? "" : "# ")\(format.fileKey): \(format.exampleFile)")
        }
        lines.append("")
        lines.append("# Files to leave out: a glob (**/Generated/**) or a fragment of the path (/Generated/)")
        if let testTarget {
            lines.append("exclude:")
            lines.append("  - \"/\(testTarget)/\"")
        } else {
            lines.append("# exclude:")
            lines.append("#   - \"\(excludeExample)\"")
        }
        return lines
    }

    private func gateSection() -> [String] {
        [
            "",
            "# Quality gate — a failed gate exits with code 2",
            "# min-score: 80",
            "# Baseline written by --write-baseline, relative to the project",
            "# baseline: .swift-mutation-testing-baseline.json",
            "# max-score-drop: 2",
            "# max-new-survivors: 0",
            "# Mutants killed or timed out without the mutated code running",
            "# max-integrity-warnings: 0",
        ]
    }

    private func mutatorsSection() -> [String] {
        var lines = [
            "",
            "# Operators up to this tier run: conservative, default or experimental.",
            "# See https://github.com/ericodx/swift-mutation-testing/blob/main/Docs/OPERATORS.md",
            "# operator-tier: default",
            "",
            "# Mutation operators — set active: false to disable",
            "mutators:",
        ]
        for name in OperatorRegistry.allOperatorNames {
            lines.append("  - name: \(name)")
            lines.append("    active: true")
        }
        return lines
    }
}
