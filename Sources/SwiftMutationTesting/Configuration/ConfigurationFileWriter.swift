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

        if project.allSchemes.count > 1 {
            lines.append("# Available schemes: \(project.allSchemes.joined(separator: ", "))")
        }

        if let scheme = project.scheme {
            lines.append("scheme: \(scheme)")
        } else {
            lines.append("# scheme: MyApp")
        }

        lines.append("destination: \(project.destination)")

        if let testTarget = project.testTarget {
            lines.append("testTarget: \(testTarget)")
        } else {
            lines.append("# testTarget: MyAppTests")
        }

        lines.append("timeout: 60")
        lines.append("concurrency: 4")
        lines.append("# output: reports/mutations.json")
        lines.append("# htmlOutput: reports/mutations.html")
        lines.append("# sonarOutput: reports/sonar.json")

        return lines.joined(separator: "\n") + "\n"
    }
}
