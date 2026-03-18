import Foundation

struct ConfigurationFileWriter: Sendable {

    private let template = """
        # scheme: MyApp
        # destination: platform=macOS
        # testTarget: MyAppTests
        # timeout: 60
        # concurrency: 4
        # output: reports/mutations.json
        # htmlOutput: reports/mutations.html
        # sonarOutput: reports/sonar.json
        """

    func write(to projectPath: String) throws {
        let fileURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".swift-mutation-testing.yml")

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UsageError(message: ".swift-mutation-testing.yml already exists at \(fileURL.path)")
        }

        try template.write(to: fileURL, atomically: true, encoding: .utf8)
        print("Created \(fileURL.path)")
    }
}
