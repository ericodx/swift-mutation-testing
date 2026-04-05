import Foundation

struct ConfigurationResolver: Sendable {
    func resolve(
        cliArguments: ParsedArguments,
        fileValues: [String: String]
    ) throws -> RunnerConfiguration {
        let projectPath = resolvedPath(cliArguments.projectPath)
        let concurrency = resolvedConcurrency(cli: cliArguments, fileValues: fileValues)

        guard concurrency >= 1 else {
            throw UsageError(message: "--concurrency must be >= 1")
        }

        let projectType = try resolveProjectType(
            cliArguments: cliArguments,
            fileValues: fileValues,
            projectPath: projectPath
        )

        let testingFramework = try resolvedTestingFramework(cli: cliArguments, fileValues: fileValues)
        let timeout = resolvedTimeout(cli: cliArguments, fileValues: fileValues, projectType: projectType)

        let effectiveConcurrency: Int
        if case .xcode = projectType, testingFramework == .xctest {
            effectiveConcurrency = 1
        } else {
            effectiveConcurrency = concurrency
        }

        return RunnerConfiguration(
            projectPath: projectPath,
            build: .init(
                projectType: projectType,
                testTarget: cliArguments.build.testTarget ?? fileValues["test-target"],
                timeout: timeout,
                concurrency: effectiveConcurrency,
                noCache: cliArguments.build.noCache || fileValues["no-cache"]?.lowercased() == "true",
                testingFramework: testingFramework
            ),
            reporting: .init(
                output: cliArguments.reporting.output ?? fileValues["output"],
                htmlOutput: cliArguments.reporting.htmlOutput ?? fileValues["html-output"],
                sonarOutput: cliArguments.reporting.sonarOutput ?? fileValues["sonar-output"],
                quiet: cliArguments.reporting.quiet || fileValues["quiet"]?.lowercased() == "true"
            ),
            filter: .init(
                sourcesPath: cliArguments.filter.sourcesPath ?? fileValues["sources-path"],
                excludePatterns: resolveList(
                    cli: cliArguments.filter.excludePatterns,
                    keys: ["exclude", "exclude-patterns"],
                    from: fileValues
                ),
                operators: resolveOperators(cli: cliArguments, fileValues: fileValues)
            )
        )
    }

    private func resolveProjectType(
        cliArguments: ParsedArguments,
        fileValues: [String: String],
        projectPath: String
    ) throws -> ProjectType {
        let scheme = cliArguments.build.scheme ?? fileValues["scheme"]
        let destination = cliArguments.build.destination ?? fileValues["destination"]

        if scheme == nil && destination == nil && hasSPMPackage(at: projectPath) {
            return .spm
        }

        guard let scheme else {
            throw UsageError(message: "--scheme is required")
        }

        guard let destination else {
            throw UsageError(message: "--destination is required")
        }

        return .xcode(scheme: scheme, destination: destination)
    }

    private func hasSPMPackage(at projectPath: String) -> Bool {
        let packageURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("Package.swift")
        return FileManager.default.fileExists(atPath: packageURL.path)
    }

    private func resolvedTimeout(cli: ParsedArguments, fileValues: [String: String], projectType: ProjectType) -> Double
    {
        if let timeout = cli.build.timeout { return timeout }
        if let timeout = fileValues["timeout"].flatMap(Double.init) { return timeout }

        return switch projectType {
        case .xcode: RunnerConfiguration.defaultXcodeTimeout
        case .spm: RunnerConfiguration.defaultSPMTimeout
        }
    }

    private func resolvedConcurrency(cli: ParsedArguments, fileValues: [String: String]) -> Int {
        if let concurrency = cli.build.concurrency { return concurrency }
        if let concurrency = fileValues["concurrency"].flatMap(Int.init) { return concurrency }
        return RunnerConfiguration.defaultConcurrency
    }

    private func resolvedTestingFramework(cli: ParsedArguments, fileValues: [String: String]) throws -> TestingFramework
    {
        let raw = cli.build.testingFramework ?? fileValues["testing-framework"]

        guard let raw else {
            return .swiftTesting
        }

        guard let framework = TestingFramework(rawValue: raw) else {
            throw UsageError(message: "--testing-framework must be 'xctest' or 'swift-testing'")
        }

        return framework
    }

    private func resolveOperators(cli: ParsedArguments, fileValues: [String: String]) -> [String] {
        if !cli.filter.operators.isEmpty {
            return cli.filter.operators
        }

        if !cli.filter.disabledMutators.isEmpty {
            let disabled = Set(cli.filter.disabledMutators)
            return DiscoveryPipeline.allOperatorNames.filter { !disabled.contains($0) }
        }

        let fileDisabled = resolveList(cli: [], keys: ["disabled-mutators"], from: fileValues)
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
