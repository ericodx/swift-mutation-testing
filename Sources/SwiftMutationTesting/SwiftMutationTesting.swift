import Foundation

@main
struct SwiftMutationTesting {
    static func main() async {
        exit(await run(args: Array(CommandLine.arguments.dropFirst())).rawValue)
    }

    static func run(args: [String]) async -> ExitCode {
        do {
            return try await execute(args: args)
        } catch let error as UsageError {
            fputs(error.message + "\n", stderr)
            return .error
        } catch BuildError.compilationFailed {
            fputs("Build-for-testing failed. Check scheme and destination.\n", stderr)
            return .error
        } catch SimulatorError.deviceNotFound(let dest) {
            fputs("Simulator not found for destination: \(dest)\n", stderr)
            return .error
        } catch SimulatorError.bootTimeout(let udid) {
            fputs("Simulator boot timeout for UDID: \(udid)\n", stderr)
            return .error
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            return .error
        }
    }

    private static func execute(args: [String]) async throws -> ExitCode {
        let parsed = try CommandLineParser().parse(args)

        if parsed.showHelp {
            print(HelpText.usage)
            return .success
        }

        if parsed.showVersion {
            print("0.1.0")
            return .success
        }

        if parsed.showInit {
            let detected = await ProjectDetector(launcher: ProcessLauncher()).detect(at: parsed.projectPath)
            try ConfigurationFileWriter().write(to: parsed.projectPath, project: detected)
            return .success
        }

        let fileValues = try ConfigurationFileParser().parse(at: parsed.projectPath)
        let configuration = try ConfigurationResolver().resolve(
            cliArguments: parsed,
            fileValues: fileValues
        )

        guard let inputPath = parsed.input ?? fileValues["input"] else {
            throw UsageError(message: "--input is required")
        }

        let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let input = try JSONDecoder().decode(RunnerInput.self, from: inputData)

        let start = Date()
        let results = try await MutantExecutor(configuration: configuration).execute(input)
        let duration = Date().timeIntervalSince(start)

        let summary = RunnerSummary(results: results, totalDuration: duration)
        TextReporter().report(summary)

        if let output = configuration.output {
            try JsonReporter(outputPath: output, projectRoot: configuration.projectPath).report(summary)
        }

        if let htmlOutput = configuration.htmlOutput {
            try HtmlReporter(outputPath: htmlOutput).report(summary)
        }

        if let sonarOutput = configuration.sonarOutput {
            try SonarReporter(outputPath: sonarOutput, projectRoot: configuration.projectPath).report(summary)
        }

        if parsed.input != nil {
            let data = try JSONEncoder().encode(results)
            print(String(data: data, encoding: .utf8) ?? "[]")
        }

        return .success
    }
}
