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

        let legacyMode = parsed.input != nil || fileValues["input"] != nil
        let input = try await discover(
            parsed: parsed, fileValues: fileValues, configuration: configuration, legacyMode: legacyMode
        )
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

        if legacyMode {
            let data = try JSONEncoder().encode(results)
            print(String(data: data, encoding: .utf8) ?? "[]")
        }

        return .success
    }

    private static func discover(
        parsed: ParsedArguments,
        fileValues: [String: String],
        configuration: RunnerConfiguration,
        legacyMode: Bool
    ) async throws -> RunnerInput {
        let start = Date()
        let input = try await buildRunnerInput(parsed: parsed, fileValues: fileValues, configuration: configuration)

        if !legacyMode && !configuration.quiet {
            let schematizable = input.mutants.filter { $0.isSchematizable }.count
            let incompatible = input.mutants.filter { !$0.isSchematizable }.count
            await ConsoleProgressReporter().report(
                .discoveryFinished(
                    mutantCount: input.mutants.count,
                    schematizableCount: schematizable,
                    incompatibleCount: incompatible,
                    duration: Date().timeIntervalSince(start)
                ))
        }

        return input
    }

    private static func buildRunnerInput(
        parsed: ParsedArguments,
        fileValues: [String: String],
        configuration: RunnerConfiguration
    ) async throws -> RunnerInput {
        if let inputPath = parsed.input ?? fileValues["input"] {
            let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
            return try JSONDecoder().decode(RunnerInput.self, from: inputData)
        }

        let discoveryInput = DiscoveryInput(
            projectPath: configuration.projectPath,
            scheme: configuration.scheme,
            destination: configuration.destination,
            timeout: configuration.timeout,
            concurrency: configuration.concurrency,
            noCache: configuration.noCache,
            sourcesPath: configuration.sourcesPath ?? configuration.projectPath,
            excludePatterns: configuration.excludePatterns,
            operators: configuration.operators
        )

        return try await DiscoveryPipeline().run(input: discoveryInput)
    }
}
