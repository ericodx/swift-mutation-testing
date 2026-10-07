import Foundation

struct ConfigurationResolver: Sendable {
    static let fileName = ".swift-mutation-testing.yml"

    static let fileKeys: Set<String> = Set(
        [
            "scheme", "destination", "workspace", "project", "test-target", "timeout", "build-timeout",
            "concurrency", "no-cache", "testing-framework", "keep-logs", "quiet", "sources-path", "exclude",
            "exclude-patterns", "operators", "disabled-mutators", "operator-tier", "min-score", "max-score-drop",
            "max-new-survivors", "max-integrity-warnings", "baseline",
        ] + ReportFormat.allCases.map(\.fileKey)
    )

    var fileSystem = FileSystem()
    var warn: @Sendable (String) -> Void = StandardError.write

    func resolve(
        cliArguments: ParsedArguments,
        fileValues: [String: String]
    ) throws -> RunnerConfiguration {
        let projectPath = fileSystem.projectPath(cliArguments.projectPath)
        warnAboutUnknownKeys(in: fileValues)
        let concurrency = try resolvedConcurrency(cli: cliArguments, fileValues: fileValues)

        let projectType = try resolveProjectType(
            cliArguments: cliArguments,
            fileValues: fileValues,
            projectPath: projectPath
        )

        let testingFramework = try resolvedTestingFramework(cli: cliArguments, fileValues: fileValues)
        let timeout = try resolvedTimeout(cli: cliArguments, fileValues: fileValues, projectType: projectType)
        let buildTimeout = try resolvedBuildTimeout(cli: cliArguments, fileValues: fileValues)

        let effectiveConcurrency = Self.effectiveConcurrency(
            requested: concurrency,
            projectType: projectType,
            testingFramework: testingFramework
        )

        let xcodeContainer = try resolveXcodeContainer(
            cli: cliArguments, fileValues: fileValues, projectType: projectType, projectPath: projectPath
        )

        return RunnerConfiguration(
            projectPath: projectPath,
            build: .init(
                projectType: projectType,
                xcodeContainer: xcodeContainer,
                testTarget: cliArguments.build.testTarget ?? fileValues["test-target"],
                timeout: timeout,
                buildTimeout: buildTimeout,
                concurrency: effectiveConcurrency,
                noCache: try cliArguments.build.noCache || flag(fileValues["no-cache"], key: "no-cache"),
                testingFramework: testingFramework
            ),
            reporting: .init(
                outputs: ReportFormat.allCases.reduce(into: [:]) { outputs, format in
                    outputs[format] = cliArguments.reporting.outputs[format] ?? fileValues[format.fileKey]
                },
                keepLogsPath: cliArguments.reporting.keepLogsPath ?? fileValues["keep-logs"],
                quiet: try cliArguments.reporting.quiet || flag(fileValues["quiet"], key: "quiet")
            ),
            filter: .init(
                sourcesPath: cliArguments.filter.sourcesPath ?? fileValues["sources-path"],
                excludePatterns: resolveList(
                    cli: cliArguments.filter.excludePatterns,
                    keys: ["exclude", "exclude-patterns"],
                    from: fileValues
                ),
                operators: try resolveOperators(cli: cliArguments, fileValues: fileValues)
            ),
            gate: try resolveGate(cli: cliArguments.gate, fileValues: fileValues, projectPath: projectPath)
        )
    }

    static func effectiveConcurrency(
        requested: Int,
        projectType: ProjectType,
        testingFramework: TestingFramework
    ) -> Int {
        guard case .xcode(_, let destination) = projectType else { return requested }
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

        let namesContainer = Self.containerFlags(cli: cliArguments, fileValues: fileValues) != (nil, nil)
        if scheme == nil && destination == nil && !namesContainer && hasSPMPackage(at: projectPath) {
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

    private static func containerFlags(
        cli: ParsedArguments, fileValues: [String: String]
    ) -> (workspace: String?, project: String?) {
        if cli.build.workspace != nil || cli.build.xcodeProject != nil {
            return (cli.build.workspace, cli.build.xcodeProject)
        }
        return (fileValues["workspace"], fileValues["project"])
    }

    private func resolveXcodeContainer(
        cli: ParsedArguments, fileValues: [String: String], projectType: ProjectType, projectPath: String
    ) throws -> XcodeContainer? {
        guard case .xcode = projectType else { return nil }
        let (workspace, project) = Self.containerFlags(cli: cli, fileValues: fileValues)
        return try XcodeContainerLocator.locate(
            in: URL(fileURLWithPath: projectPath), workspace: workspace, project: project, fileSystem: fileSystem)
    }

    private func hasSPMPackage(at projectPath: String) -> Bool {
        let packageURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("Package.swift")
        return fileSystem.fileExists(packageURL.path)
    }

    private func resolvedTimeout(
        cli: ParsedArguments, fileValues: [String: String], projectType: ProjectType
    ) throws -> Double {
        if let timeout = cli.build.timeout { return timeout }
        if let timeout = try positiveNumber(fileValues["timeout"], key: "timeout") { return timeout }

        return switch projectType {
        case .xcode: RunnerConfiguration.defaultXcodeTimeout
        case .spm: RunnerConfiguration.defaultSPMTimeout
        }
    }

    private func resolvedBuildTimeout(cli: ParsedArguments, fileValues: [String: String]) throws -> Double {
        if let buildTimeout = cli.build.buildTimeout { return buildTimeout }
        if let buildTimeout = try positiveNumber(fileValues["build-timeout"], key: "build-timeout") {
            return buildTimeout
        }
        return RunnerConfiguration.defaultBuildTimeout
    }

    private func resolvedConcurrency(cli: ParsedArguments, fileValues: [String: String]) throws -> Int {
        if let concurrency = cli.build.concurrency {
            guard concurrency >= 1 else { throw UsageError(message: "--concurrency must be >= 1") }
            return concurrency
        }
        if let concurrency = try number(fileValues["concurrency"], key: "concurrency", as: Int.self) {
            guard concurrency >= 1 else {
                throw UsageError(message: "concurrency in \(Self.fileName) must be >= 1")
            }
            return concurrency
        }
        return RunnerConfiguration.defaultConcurrency
    }

    private func warnAboutUnknownKeys(in fileValues: [String: String]) {
        for key in fileValues.keys.sorted() where !Self.fileKeys.contains(key) {
            warn("Warning: unknown key '\(key)' in \(Self.fileName) is ignored")
        }
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

    private func resolveOperators(cli: ParsedArguments, fileValues: [String: String]) throws -> [String] {
        let explicit = resolveList(cli: cli.filter.operators, keys: ["operators"], from: fileValues)
        if !explicit.isEmpty {
            return explicit
        }

        let tier = try resolvedOperatorTier(cli: cli, fileValues: fileValues)
        let fileDisabled = resolveList(cli: [], keys: ["disabled-mutators"], from: fileValues)
        let disabled = Set(cli.filter.disabledMutators + fileDisabled)

        return OperatorRegistry.operatorNames(upTo: tier).filter { !disabled.contains($0) }
    }

    private func resolvedOperatorTier(cli: ParsedArguments, fileValues: [String: String]) throws -> OperatorTier {
        guard let raw = cli.filter.operatorTier ?? fileValues["operator-tier"] else {
            return .standard
        }

        guard let tier = OperatorTier(rawValue: raw) else {
            throw UsageError(message: OperatorTier.usage)
        }

        return tier
    }

    private func resolveGate(
        cli: ParsedArguments.GateOptions,
        fileValues: [String: String],
        projectPath: String
    ) throws -> RunnerConfiguration.GateOptions {
        let policy = GatePolicy(
            minScore: try cli.minScore ?? number(fileValues["min-score"], key: "min-score", as: Double.self),
            maxScoreDrop: try cli.maxScoreDrop
                ?? number(fileValues["max-score-drop"], key: "max-score-drop", as: Double.self),
            maxNewSurvivors: try cli.maxNewSurvivors
                ?? number(fileValues["max-new-survivors"], key: "max-new-survivors", as: Int.self),
            maxIntegrityWarnings: try cli.maxIntegrityWarnings
                ?? number(fileValues["max-integrity-warnings"], key: "max-integrity-warnings", as: Int.self)
        )
        let baseline = (cli.baseline ?? fileValues["baseline"]).map { projectRelative($0, in: projectPath) }

        if let minScore = policy.minScore, !(0 ... 100).contains(minScore) {
            throw UsageError(message: "--min-score must be between 0 and 100")
        }
        if let maxScoreDrop = policy.maxScoreDrop, maxScoreDrop < 0 {
            throw UsageError(message: "--max-score-drop must be a number >= 0")
        }
        if let maxNewSurvivors = policy.maxNewSurvivors, maxNewSurvivors < 0 {
            throw UsageError(message: "--max-new-survivors must be >= 0")
        }
        if let maxIntegrityWarnings = policy.maxIntegrityWarnings, maxIntegrityWarnings < 0 {
            throw UsageError(message: "--max-integrity-warnings must be >= 0")
        }
        if baseline == nil, policy.maxScoreDrop != nil || policy.maxNewSurvivors != nil {
            throw UsageError(message: "--max-score-drop and --max-new-survivors need --baseline")
        }
        if let baseline, !fileSystem.fileExists(baseline) {
            throw UsageError(message: "baseline '\(baseline)' does not exist; write one with --write-baseline")
        }

        return RunnerConfiguration.GateOptions(
            policy: policy,
            baselinePath: baseline,
            writeBaselinePath: cli.writeBaseline.map { projectRelative($0, in: projectPath) }
        )
    }

    private func number<Value: LosslessStringConvertible>(
        _ raw: String?,
        key: String,
        as _: Value.Type
    ) throws -> Value? {
        guard let raw else { return nil }
        guard let value = Value(raw) else {
            throw UsageError(message: "\(key) in \(Self.fileName) must be a number")
        }
        return value
    }

    private func positiveNumber(_ raw: String?, key: String) throws -> Double? {
        guard let value = try number(raw, key: key, as: Double.self) else { return nil }
        guard value > 0 else {
            throw UsageError(message: "\(key) in \(Self.fileName) must be a positive number")
        }
        return value
    }

    private func flag(_ raw: String?, key: String) throws -> Bool {
        guard let raw else { return false }
        switch raw.lowercased() {
        case "true", "yes", "on": return true
        case "false", "no", "off": return false
        default: throw UsageError(message: "\(key) in \(Self.fileName) must be true or false")
        }
    }

    private func projectRelative(_ path: String, in projectPath: String) -> String {
        guard !path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: projectPath).appendingPathComponent(path).standardizedFileURL.path
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
