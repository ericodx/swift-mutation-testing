import Foundation

@main
struct SwiftMutationTesting {

    static func main() async {
        exit(await run(args: Array(CommandLine.arguments.dropFirst())).rawValue)
    }

    static func run(args: [String], launcher: any ProcessLaunching = ProcessLauncher()) async -> ExitCode {
        do {
            return try await execute(args: args, launcher: launcher)
        } catch let error as UsageError {
            fputs(error.message + "\n", stderr)
            return .error
        } catch SimulatorError.deviceNotFound(let dest) {
            fputs("Simulator not found for destination: \(dest)\n", stderr)
            return .error
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            return .error
        }
    }

    private static func execute(args: [String], launcher: any ProcessLaunching) async throws -> ExitCode {
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
            let detected = await ProjectDetector(launcher: launcher).detect(at: parsed.projectPath)
            try ConfigurationFileWriter().write(to: parsed.projectPath, project: detected)
            return .success
        }

        let fileValues = try ConfigurationFileParser().parse(at: parsed.projectPath)
        let configuration = try ConfigurationResolver().resolve(
            cliArguments: parsed,
            fileValues: fileValues
        )

        let input = try await discover(configuration: configuration)
        let start = Date()
        let results = try await MutantExecutor(configuration: configuration, launcher: launcher).execute(input)
        let duration = Date().timeIntervalSince(start)

        let summary = RunnerSummary(results: results, totalDuration: duration)
        TextReporter(projectRoot: configuration.projectPath).report(summary)
        writeReports(summary, configuration: configuration)

        return .success
    }

    private static func discover(configuration: RunnerConfiguration) async throws -> RunnerInput {
        let start = Date()
        let discoveryInput = DiscoveryInput(
            projectPath: configuration.projectPath,
            scheme: configuration.build.scheme,
            destination: configuration.build.destination,
            timeout: configuration.build.timeout,
            concurrency: configuration.build.concurrency,
            noCache: configuration.build.noCache,
            sourcesPath: configuration.filter.sourcesPath ?? configuration.projectPath,
            excludePatterns: configuration.filter.excludePatterns,
            operators: configuration.filter.operators
        )
        let input = try await DiscoveryPipeline().run(input: discoveryInput)

        if !configuration.reporting.quiet {
            let schematizable = input.mutants.filter { $0.isSchematizable }.count
            let incompatible = input.mutants.count - schematizable
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

    static func writeReports(_ summary: RunnerSummary, configuration: RunnerConfiguration) {
        let hasReports =
            configuration.reporting.output != nil
            || configuration.reporting.htmlOutput != nil
            || configuration.reporting.sonarOutput != nil
        guard hasReports else { return }
        print("")

        if let output = configuration.reporting.output {
            do {
                try JsonReporter(outputPath: output, projectRoot: configuration.projectPath).report(summary)
                print("  ✓ JSON report: \(output)")
            } catch {
                fputs("Warning: could not write JSON report to '\(output)': \(error.localizedDescription)\n", stderr)
            }
        }

        if let htmlOutput = configuration.reporting.htmlOutput {
            do {
                try HtmlReporter(outputPath: htmlOutput, projectRoot: configuration.projectPath).report(summary)
                print("  ✓ HTML report: \(htmlOutput)")
            } catch {
                let msg = "Warning: could not write HTML report to '\(htmlOutput)': \(error.localizedDescription)\n"
                fputs(msg, stderr)
            }
        }

        if let sonarOutput = configuration.reporting.sonarOutput {
            do {
                try SonarReporter(outputPath: sonarOutput, projectRoot: configuration.projectPath).report(summary)
                print("  ✓ Sonar report: \(sonarOutput)")
            } catch {
                let msg = "Warning: could not write Sonar report to '\(sonarOutput)': \(error.localizedDescription)\n"
                fputs(msg, stderr)
            }
        }
    }
}
