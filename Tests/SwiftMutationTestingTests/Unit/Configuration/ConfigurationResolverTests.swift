import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationResolver")
struct ConfigurationResolverTests {
    private let resolver = IsolatedResolver()

    @Test("Given CLI scheme and destination, when resolved, then projectType is xcode with CLI values")
    func usesCLIValues() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "MyApp", destination: "platform=macOS")),
            fileValues: [:]
        )

        #expect(result.build.projectType == .xcode(scheme: "MyApp", destination: "platform=macOS"))
    }

    @Test("Given scheme and destination only in file, when resolved, then projectType is xcode with file values")
    func fallsBackToFileValues() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(),
            fileValues: ["scheme": "FileApp", "destination": "platform=macOS"]
        )

        #expect(result.build.projectType == .xcode(scheme: "FileApp", destination: "platform=macOS"))
    }

    @Test("Given scheme in both CLI and file, when resolved, then CLI scheme takes priority")
    func cliSchemeOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "CLIApp", destination: "platform=macOS")),
            fileValues: ["scheme": "FileApp"]
        )

        #expect(result.build.projectType == .xcode(scheme: "CLIApp", destination: "platform=macOS"))
    }

    @Test("Given Package.swift present and no scheme or destination, when resolved, then projectType is spm")
    func detectsSPMWhenPackageSwiftExists() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("// Package.swift", named: "Package.swift", in: dir)

        let result = try resolver.resolve(
            cliArguments: ParsedArguments(projectPath: dir.path),
            fileValues: [:]
        )

        #expect(result.build.projectType == .spm)
    }

    @Test("Given Package.swift present but scheme provided, when resolved, then projectType is xcode")
    func xcodeWhenSchemeProvidedEvenWithPackageSwift() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("// Package.swift", named: "Package.swift", in: dir)

        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                projectPath: dir.path,
                build: .init(scheme: "MyApp", destination: "platform=macOS")
            ),
            fileValues: [:]
        )

        #expect(result.build.projectType == .xcode(scheme: "MyApp", destination: "platform=macOS"))
    }

    @Test("Given no scheme and no Package.swift, when resolved, then throws UsageError")
    func throwsWhenSchemeMissingAndNotSPM() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(build: .init(destination: "platform=macOS")),
                fileValues: [:]
            )
        }
    }

    @Test("Given no destination and scheme provided, when resolved, then throws UsageError")
    func throwsWhenDestinationMissing() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(build: .init(scheme: "MyApp")),
                fileValues: [:]
            )
        }
    }

    @Test("Given timeout only in file, when resolved, then configuration uses file timeout")
    func fileTimeoutUsedWhenCLIOmits() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["timeout": "120"]
        )

        #expect(result.build.timeout == 120)
    }

    @Test("Given timeout in both CLI and file, when resolved, then CLI timeout takes priority")
    func cliTimeoutOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", timeout: 30)),
            fileValues: ["timeout": "120"]
        )

        #expect(result.build.timeout == 30)
    }

    @Test("Given build-timeout only in file, when resolved, then configuration uses it")
    func buildTimeoutFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["build-timeout": "240"]
        )

        #expect(result.build.buildTimeout == 240)
    }

    @Test("Given build-timeout in both CLI and file, when resolved, then CLI takes priority")
    func buildTimeoutCLIWinsOverFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", buildTimeout: 90)),
            fileValues: ["build-timeout": "240"]
        )

        #expect(result.build.buildTimeout == 90)
    }

    @Test(
        "Given no build-timeout anywhere, when resolved, then the build default is applied and test timeout is untouched"
    )
    func buildTimeoutFallsBackToDefault() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", timeout: 30)),
            fileValues: [:]
        )

        #expect(result.build.buildTimeout == RunnerConfiguration.defaultBuildTimeout)
        #expect(result.build.timeout == 30)
    }

    @Test("Given no timeout in CLI or file for Xcode, when resolved, then default Xcode timeout is applied")
    func appliesDefaultXcodeTimeout() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: [:]
        )

        #expect(result.build.timeout == RunnerConfiguration.defaultXcodeTimeout)
    }

    @Test("Given no timeout in CLI or file for SPM, when resolved, then default SPM timeout is applied")
    func appliesDefaultSPMTimeout() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("// Package.swift", named: "Package.swift", in: dir)

        let result = try resolver.resolve(
            cliArguments: ParsedArguments(projectPath: dir.path),
            fileValues: [:]
        )

        #expect(result.build.timeout == RunnerConfiguration.defaultSPMTimeout)
    }

    @Test("Given no concurrency in CLI or file, when resolved, then default concurrency is applied")
    func appliesDefaultConcurrency() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: [:]
        )

        #expect(result.build.concurrency == RunnerConfiguration.defaultConcurrency)
    }

    @Test("Given noCache true in file, when resolved, then noCache is true")
    func noCacheFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["no-cache": "true"]
        )

        #expect(result.build.noCache)
    }

    @Test("Given quiet true in file, when resolved, then quiet is true")
    func quietFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["quiet": "true"]
        )

        #expect(result.reporting.quiet)
    }

    @Test("Given concurrency of zero, when resolved, then throws UsageError")
    func throwsWhenConcurrencyLessThanOne() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", concurrency: 0)),
                fileValues: [:]
            )
        }
    }

    @Test("Given --sources-path via CLI, when resolved, then sourcesPath is set")
    func sourcesPathFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(sourcesPath: "/my/sources")
            ),
            fileValues: [:]
        )

        #expect(result.filter.sourcesPath == "/my/sources")
    }

    @Test("Given sourcesPath only in file, when resolved, then sourcesPath uses file value")
    func sourcesPathFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["sources-path": "/file/sources"]
        )

        #expect(result.filter.sourcesPath == "/file/sources")
    }

    @Test("Given no sourcesPath anywhere, when resolved, then sourcesPath is nil")
    func sourcesPathDefaultsToNil() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: [:]
        )

        #expect(result.filter.sourcesPath == nil)
    }

    @Test("Given --exclude patterns via CLI, when resolved, then excludePatterns are set")
    func excludePatternsFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(excludePatterns: ["/Generated/", "/Pods/"])
            ),
            fileValues: [:]
        )

        #expect(result.filter.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given excludePatterns only in file as comma-separated, when resolved, then list is split")
    func excludePatternsFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["exclude-patterns": "/Generated/,/Pods/"]
        )

        #expect(result.filter.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given exclude as YAML list key in file, when resolved, then list is parsed")
    func excludeFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["exclude": "/Generated/,/Pods/"]
        )

        #expect(result.filter.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given --operator via CLI, when resolved, then operators are set")
    func operatorsFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(operators: ["BooleanLiteralReplacement", "NegateConditional"])
            ),
            fileValues: [:]
        )

        #expect(result.filter.operators == ["BooleanLiteralReplacement", "NegateConditional"])
    }

    @Test("Given operators only in file as comma-separated, when resolved, then list is split")
    func operatorsFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["operators": "BooleanLiteralReplacement,NegateConditional"]
        )

        #expect(result.filter.operators == ["BooleanLiteralReplacement", "NegateConditional"])
    }

    @Test("Given disabledMutators in file, when resolved, then operators excludes them")
    func disabledMutatorsFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["disabled-mutators": "RemoveSideEffects,SwapTernary"]
        )

        #expect(!result.filter.operators.contains("RemoveSideEffects"))
        #expect(!result.filter.operators.contains("SwapTernary"))
        #expect(result.filter.operators.contains("NegateConditional"))
    }

    @Test("Given --disable-mutator via CLI, when resolved, then operators excludes it")
    func disabledMutatorsFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(disabledMutators: ["RemoveSideEffects"])
            ),
            fileValues: [:]
        )

        #expect(!result.filter.operators.contains("RemoveSideEffects"))
        #expect(result.filter.operators.contains("NegateConditional"))
    }

    @Test("Given every operator of the tier disabled, when resolved, then it is a usage error, not every operator")
    func disablingTheWholeTierIsAUsageError() {
        let error = #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(
                    build: .init(scheme: "App", destination: "d"),
                    filter: .init(disabledMutators: ["LogicalOperatorReplacement", "NegateConditional"])
                ),
                fileValues: ["disabled-mutators": "SwapTernary"]
            )
        }

        #expect(error?.message.contains("'default' tier") == true)
    }

    @Test("Given the default tier disabled but a larger tier chosen, when resolved, then the rest of that tier runs")
    func disablingTheDefaultTierLeavesALargerTierItsOtherOperators() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(
                    disabledMutators: ["LogicalOperatorReplacement", "NegateConditional", "SwapTernary"],
                    operatorTier: "experimental"
                )
            ),
            fileValues: [:]
        )

        #expect(result.filter.operators.contains("RemoveSideEffects"))
        #expect(!result.filter.operators.contains("SwapTernary"))
    }

    @Test("Given --operator via CLI and disabledMutators in file, when resolved, then CLI --operator wins")
    func cliOperatorOverridesDisabledMutators() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(operators: ["NegateConditional"])
            ),
            fileValues: ["disabled-mutators": "NegateConditional"]
        )

        #expect(result.filter.operators == ["NegateConditional"])
    }

    @Test("Given no operators and no tier anywhere, when resolved, then the default tier's operators run")
    func operatorsDefaultToTheDefaultTier() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: [:]
        )

        #expect(result.filter.operators == OperatorRegistry.operatorNames(upTo: .standard))
    }

    @Test("Given --operator-tier via CLI, when resolved, then the operators up to that tier run")
    func operatorTierFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(operatorTier: "experimental")
            ),
            fileValues: [:]
        )

        #expect(result.filter.operators == OperatorRegistry.operatorNames(upTo: .experimental))
    }

    @Test("Given operator-tier in file, when resolved, then the operators up to that tier run")
    func operatorTierFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["operator-tier": "conservative"]
        )

        #expect(result.filter.operators == OperatorRegistry.operatorNames(upTo: .conservative))
    }

    @Test("Given --operator-tier via CLI and operator-tier in file, when resolved, then the CLI tier wins")
    func cliOperatorTierOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(operatorTier: "experimental")
            ),
            fileValues: ["operator-tier": "conservative"]
        )

        #expect(result.filter.operators == OperatorRegistry.operatorNames(upTo: .experimental))
    }

    @Test("Given a tier that does not exist, when resolved, then throws UsageError naming the three tiers")
    func anUnknownOperatorTierIsAUsageError() throws {
        let error = #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
                fileValues: ["operator-tier": "stable"]
            )
        }

        #expect(error?.message == "--operator-tier must be 'conservative', 'default' or 'experimental'")
    }

    @Test("Given --operator and --operator-tier, when resolved, then the explicit list runs, whatever its tier")
    func explicitOperatorsIgnoreTheTier() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(operators: ["RemoveSideEffects"], operatorTier: "conservative")
            ),
            fileValues: [:]
        )

        #expect(result.filter.operators == ["RemoveSideEffects"])
    }

    @Test("Given operators and disabled-mutators both in file, when resolved, then the explicit list runs")
    func fileOperatorsOverrideFileDisabledMutators() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["operators": "NegateConditional", "disabled-mutators": "NegateConditional"]
        )

        #expect(result.filter.operators == ["NegateConditional"])
    }

    @Test(
        "Given --disable-mutator via CLI and disabled-mutators in file, when resolved, then both leave the tier's set")
    func cliAndFileDisabledMutatorsAreBothRemoved() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d"),
                filter: .init(disabledMutators: ["RemoveSideEffects"], operatorTier: "experimental")
            ),
            fileValues: ["disabled-mutators": "SwapTernary"]
        )

        let expected = OperatorRegistry.operatorNames(upTo: .experimental)
            .filter { $0 != "RemoveSideEffects" && $0 != "SwapTernary" }
        #expect(result.filter.operators == expected)
    }

    @Test("Given concurrency only in file, when resolved, then configuration uses file concurrency")
    func fileConcurrencyUsedWhenCLIOmits() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["concurrency": "8"]
        )

        #expect(result.build.concurrency == 8)
    }

    @Test("Given explicit project path, when resolved, then path is standardized")
    func explicitProjectPathIsStandardized() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                projectPath: "/tmp/myapp",
                build: .init(scheme: "App", destination: "d")
            ),
            fileValues: [:]
        )

        #expect(result.projectPath.hasSuffix("myapp"))
    }

    @Test("Given empty project path, when resolved, then uses current directory")
    func emptyProjectPathUsesCurrentDirectory() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(projectPath: ""),
            fileValues: [:]
        )

        #expect(!result.projectPath.isEmpty)
    }

    @Test("Given CLI concurrency, when resolved, then CLI concurrency overrides file")
    func cliConcurrencyOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", concurrency: 2)),
            fileValues: ["concurrency": "8"]
        )

        #expect(result.build.concurrency == 2)
    }

    @Test("Given output path in file, when resolved, then output is set")
    func outputFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["output": "/tmp/report.txt"]
        )

        #expect(result.reporting.outputs[.json] == "/tmp/report.txt")
    }

    @Test("Given no testingFramework anywhere, when resolved, then defaults to swiftTesting")
    func testingFrameworkDefaultsToSwiftTesting() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: [:]
        )

        #expect(result.build.testingFramework == .swiftTesting)
    }

    @Test("Given testingFramework xctest via CLI, when resolved, then testingFramework is xctest")
    func testingFrameworkFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", testingFramework: "xctest")),
            fileValues: [:]
        )

        #expect(result.build.testingFramework == .xctest)
    }

    @Test("Given testingFramework xctest in file, when resolved, then testingFramework is xctest")
    func testingFrameworkFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d")),
            fileValues: ["testing-framework": "xctest"]
        )

        #expect(result.build.testingFramework == .xctest)
    }

    @Test("Given testingFramework in both CLI and file, when resolved, then CLI takes priority")
    func testingFrameworkCLIOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", testingFramework: "xctest")),
            fileValues: ["testing-framework": "swift-testing"]
        )

        #expect(result.build.testingFramework == .xctest)
    }

    @Test("Given invalid testingFramework value, when resolved, then throws UsageError")
    func testingFrameworkThrowsForInvalidValue() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", testingFramework: "junit")),
                fileValues: [:]
            )
        }
    }

    @Test("Given xctest and xcode project, when resolved, then concurrency is forced to 1")
    func xcTestForcesConcurrencyToOne() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d", concurrency: 8, testingFramework: "xctest")
            ),
            fileValues: [:]
        )

        #expect(result.build.concurrency == 1)
    }

    @Test("Given swift-testing and xcode project, when resolved, then concurrency is preserved")
    func swiftTestingPreservesConcurrency() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "d", concurrency: 8, testingFramework: "swift-testing")
            ),
            fileValues: [:]
        )

        #expect(result.build.concurrency == 8)
    }

    @Test("Given an spm project, when resolved, then concurrency is kept whatever the framework")
    func spmKeepsConcurrency() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write("// Package.swift", named: "Package.swift", in: dir)

        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                projectPath: dir.path,
                build: .init(concurrency: 4, testingFramework: "xctest")
            ),
            fileValues: [:]
        )

        #expect(result.build.concurrency == 4)
    }

    @Test("Given testTarget via CLI, when resolved, then testTarget is set")
    func testTargetFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "d", testTarget: "AppTests")),
            fileValues: [:]
        )

        #expect(result.build.testTarget == "AppTests")
    }

    @Test("Given build-timeout written in the config file, when parsed and resolved, then it reaches the configuration")
    func buildTimeoutSurvivesTheConfigFileRoundTrip() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try """
        scheme: App
        destination: platform=macOS
        timeout: 30
        build-timeout: 240
        """
        .write(
            to: dir.appendingPathComponent(".swift-mutation-testing.yml"),
            atomically: true,
            encoding: .utf8
        )

        let fileValues = try ConfigurationFileParser().parse(at: dir.path)
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(projectPath: dir.path),
            fileValues: fileValues
        )

        #expect(result.build.buildTimeout == 240)
        #expect(result.build.timeout == 30)
    }

    @Test("Given SARIF and Markdown paths in the file, when resolved, then both reports are configured")
    func readsSarifAndMarkdownOutputsFromTheFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(build: .init(scheme: "App", destination: "platform=macOS")),
            fileValues: ["sarif-output": "file.sarif", "markdown-output": "file.md"]
        )

        #expect(result.reporting.outputs[.sarif] == "file.sarif")
        #expect(result.reporting.outputs[.markdown] == "file.md")
    }

    @Test("Given SARIF and Markdown paths in both places, when resolved, then the command line wins")
    func commandLineSarifAndMarkdownOutputsWin() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                build: .init(scheme: "App", destination: "platform=macOS"),
                reporting: .init(outputs: [.sarif: "cli.sarif", .markdown: "cli.md"])
            ),
            fileValues: ["sarif-output": "file.sarif", "markdown-output": "file.md"]
        )

        #expect(result.reporting.outputs[.sarif] == "cli.sarif")
        #expect(result.reporting.outputs[.markdown] == "cli.md")
    }
}

private struct IsolatedResolver {
    static let emptyRoot: String = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swift-mutation-testing-empty-root")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }()

    func resolve(cliArguments: ParsedArguments, fileValues: [String: String]) throws -> RunnerConfiguration {
        var arguments = cliArguments
        if arguments.projectPath == "." {
            arguments.projectPath = Self.emptyRoot
        }
        return try ConfigurationResolver().resolve(cliArguments: arguments, fileValues: fileValues)
    }
}
