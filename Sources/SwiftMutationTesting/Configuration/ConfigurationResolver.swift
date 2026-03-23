import Foundation

struct ConfigurationResolver: Sendable {
    func resolve(
        cliArguments: ParsedArguments,
        fileValues: [String: String]
    ) throws -> RunnerConfiguration {
        let projectPath = resolvedPath(cliArguments.projectPath)
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

        guard cliArguments.scheme != nil || fileValues["scheme"] != nil else {
            throw UsageError(message: "--scheme is required")
        }

        guard cliArguments.destination != nil || fileValues["destination"] != nil else {
            throw UsageError(message: "--destination is required")
        }

        return RunnerConfiguration(
            projectPath: projectPath,
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
            excludePatterns: resolveList(
                cli: cliArguments.excludePatterns,
                keys: ["exclude", "excludePatterns"],
                from: fileValues
            ),
            operators: resolveOperators(cli: cliArguments, fileValues: fileValues)
        )
    }

    private func resolveOperators(cli: ParsedArguments, fileValues: [String: String]) -> [String] {
        if !cli.operators.isEmpty {
            return cli.operators
        }

        if !cli.disabledMutators.isEmpty {
            let disabled = Set(cli.disabledMutators)
            return DiscoveryPipeline.allOperatorNames.filter { !disabled.contains($0) }
        }

        let fileDisabled = resolveList(cli: [], keys: ["disabledMutators"], from: fileValues)
        if !fileDisabled.isEmpty {
            let disabled = Set(fileDisabled)
            return DiscoveryPipeline.allOperatorNames.filter { !disabled.contains($0) }
        }

        return resolveList(cli: [], keys: ["operators"], from: fileValues)
    }

    private func resolvedPath(_ path: String) -> String {
        if path == "." || path.isEmpty {
            return FileManager.default.currentDirectoryPath
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private func resolveList(cli: [String], keys: [String], from fileValues: [String: String]) -> [String] {
        guard cli.isEmpty else { return cli }
        for key in keys {
            if let raw = fileValues[key] {
                return
                    raw
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }
}
