struct ConfigurationResolver: Sendable {
    func resolve(
        cliArguments: ParsedArguments,
        fileValues: [String: String]
    ) throws -> RunnerConfiguration {
        let timeout: Double
        if let cliTimeout = cliArguments.timeout {
            timeout = cliTimeout
        } else if let fileTimeout = fileValues["timeout"].flatMap(Double.init) {
            timeout = fileTimeout
        } else {
            timeout = RunnerConfiguration.defaultTimeout
        }

        let concurrency: Int
        if let cliConcurrency = cliArguments.concurrency {
            concurrency = cliConcurrency
        } else if let fileConcurrency = fileValues["concurrency"].flatMap(Int.init) {
            concurrency = fileConcurrency
        } else {
            concurrency = RunnerConfiguration.defaultConcurrency
        }

        guard concurrency >= 1 else {
            throw UsageError(message: "--concurrency must be >= 1")
        }

        let hasInput = cliArguments.input != nil || fileValues["input"] != nil

        if !hasInput {
            guard cliArguments.scheme != nil || fileValues["scheme"] != nil else {
                throw UsageError(message: "--scheme is required")
            }

            guard cliArguments.destination != nil || fileValues["destination"] != nil else {
                throw UsageError(message: "--destination is required")
            }
        }

        return RunnerConfiguration(
            projectPath: cliArguments.projectPath,
            scheme: cliArguments.scheme ?? fileValues["scheme"] ?? "",
            destination: cliArguments.destination ?? fileValues["destination"] ?? "",
            testTarget: cliArguments.testTarget ?? fileValues["testTarget"],
            timeout: timeout,
            concurrency: concurrency,
            noCache: cliArguments.noCache || fileValues["noCache"]?.lowercased() == "true",
            output: cliArguments.output ?? fileValues["output"],
            htmlOutput: cliArguments.htmlOutput ?? fileValues["htmlOutput"],
            sonarOutput: cliArguments.sonarOutput ?? fileValues["sonarOutput"],
            quiet: cliArguments.quiet || fileValues["quiet"]?.lowercased() == "true",
            sourcesPath: cliArguments.sourcesPath ?? fileValues["sourcesPath"],
            excludePatterns: resolveList(cli: cliArguments.excludePatterns, key: "excludePatterns", from: fileValues),
            operators: resolveList(cli: cliArguments.operators, key: "operators", from: fileValues)
        )
    }

    private func resolveList(cli: [String], key: String, from fileValues: [String: String]) -> [String] {
        guard cli.isEmpty else { return cli }
        return fileValues[key]?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
    }
}
