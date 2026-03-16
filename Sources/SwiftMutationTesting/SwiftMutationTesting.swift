import Foundation

@main
struct SwiftMutationTesting {
    static func main() async {
        do {
            try await run()
        } catch let error as UsageError {
            fputs("error: \(error.message)\n", stderr)
            exit(ExitCode.error)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(ExitCode.error)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let parsed = try CommandLineParser().parse(arguments)

        if parsed.showHelp {
            print(HelpText.usage)
            exit(ExitCode.success)
        }

        if parsed.showVersion {
            print("0.1.0")
            exit(ExitCode.success)
        }

        let fileValues = try ConfigurationFileParser().parse(at: parsed.projectPath)
        _ = try ConfigurationResolver().resolve(
            cliArguments: parsed,
            fileValues: fileValues
        )
    }
}
