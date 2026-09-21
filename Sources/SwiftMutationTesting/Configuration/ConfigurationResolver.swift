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

        let effectiveConcurrency = Self.effectiveConcurrency(
            requested: concurrency,
            projectType: projectType,
            testingFramework: testingFramework
        )

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
                keepLogsPath: cliArguments.reporting.keepLogsPath ?? fileValues["keep-logs"],
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

    /// How many mutants can genuinely be tested at once.
    ///
    /// Workers are handed out by `SimulatorPool`, which only has more than one slot when it has
    /// cloned simulators to hand out. A run with no simulators — every SPM package, and any Xcode
    /// scheme targeting macOS — gets a single slot however high `--concurrency` is set, so the
    /// figure is resolved down to what the run can actually do rather than left to mislead (issue
    /// #70).
    ///
    /// Raising it without giving each worker its own build directory would not help anyway: they
    /// would share one `.build`, serialise on SwiftPM's lock, and count the wait against each
    /// mutant's timeout.
    static func effectiveConcurrency(
        requested: Int,
        projectType: ProjectType,
        testingFramework: TestingFramework
    ) -> Int {
        guard case .xcode(_, let destination) = projectType else { return 1 }
        guard SimulatorManager.requiresSimulatorPool(for: destination) else { return 1 }
        guard testingFramework != .xctest else { return 1 }

        return requested
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
