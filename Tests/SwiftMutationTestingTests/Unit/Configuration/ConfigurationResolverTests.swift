import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationResolver")
struct ConfigurationResolverTests {
    private let resolver = ConfigurationResolver()

    @Test("Given CLI scheme and destination, when resolved, then configuration uses CLI values")
    func usesCLIValues() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "MyApp", destination: "platform=macOS"),
            fileValues: [:]
        )

        #expect(result.scheme == "MyApp")
        #expect(result.destination == "platform=macOS")
    }

    @Test("Given scheme and destination only in file, when resolved, then configuration uses file values")
    func fallsBackToFileValues() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(),
            fileValues: ["scheme": "FileApp", "destination": "platform=macOS"]
        )

        #expect(result.scheme == "FileApp")
        #expect(result.destination == "platform=macOS")
    }

    @Test("Given scheme in both CLI and file, when resolved, then CLI scheme takes priority")
    func cliSchemeOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "CLIApp", destination: "platform=macOS"),
            fileValues: ["scheme": "FileApp"]
        )

        #expect(result.scheme == "CLIApp")
    }

    @Test("Given timeout only in file, when resolved, then configuration uses file timeout")
    func fileTimeoutUsedWhenCLIOmits() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["timeout": "120"]
        )

        #expect(result.timeout == 120)
    }

    @Test("Given timeout in both CLI and file, when resolved, then CLI timeout takes priority")
    func cliTimeoutOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", timeout: 30),
            fileValues: ["timeout": "120"]
        )

        #expect(result.timeout == 30)
    }

    @Test("Given no timeout in CLI or file, when resolved, then default timeout is applied")
    func appliesDefaultTimeout() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.timeout == RunnerConfiguration.defaultTimeout)
    }

    @Test("Given no concurrency in CLI or file, when resolved, then default concurrency is applied")
    func appliesDefaultConcurrency() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.concurrency == RunnerConfiguration.defaultConcurrency)
    }

    @Test("Given no scheme in standalone mode, when resolved, then throws UsageError")
    func throwsWhenSchemeMissing() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(destination: "platform=macOS"),
                fileValues: [:]
            )
        }
    }

    @Test("Given no destination in standalone mode, when resolved, then throws UsageError")
    func throwsWhenDestinationMissing() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(scheme: "MyApp"),
                fileValues: [:]
            )
        }
    }

    @Test("Given noCache true in file, when resolved, then noCache is true")
    func noCacheFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["noCache": "true"]
        )

        #expect(result.noCache == true)
    }

    @Test("Given quiet true in file, when resolved, then quiet is true")
    func quietFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["quiet": "true"]
        )

        #expect(result.quiet == true)
    }

    @Test("Given concurrency of zero, when resolved, then throws UsageError")
    func throwsWhenConcurrencyLessThanOne() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(scheme: "App", destination: "d", concurrency: 0),
                fileValues: [:]
            )
        }
    }

    @Test("Given --sources-path via CLI, when resolved, then sourcesPath is set")
    func sourcesPathFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", sourcesPath: "/my/sources"),
            fileValues: [:]
        )

        #expect(result.sourcesPath == "/my/sources")
    }

    @Test("Given sourcesPath only in file, when resolved, then sourcesPath uses file value")
    func sourcesPathFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["sourcesPath": "/file/sources"]
        )

        #expect(result.sourcesPath == "/file/sources")
    }

    @Test("Given no sourcesPath anywhere, when resolved, then sourcesPath is nil")
    func sourcesPathDefaultsToNil() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.sourcesPath == nil)
    }

    @Test("Given --exclude patterns via CLI, when resolved, then excludePatterns are set")
    func excludePatternsFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                scheme: "App", destination: "d", excludePatterns: ["/Generated/", "/Pods/"]),
            fileValues: [:]
        )

        #expect(result.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given excludePatterns only in file as comma-separated, when resolved, then list is split")
    func excludePatternsFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["excludePatterns": "/Generated/,/Pods/"]
        )

        #expect(result.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given exclude as YAML list key in file, when resolved, then list is parsed")
    func excludeFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["exclude": "/Generated/,/Pods/"]
        )

        #expect(result.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given --operator via CLI, when resolved, then operators are set")
    func operatorsFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(
                scheme: "App", destination: "d",
                operators: ["BooleanLiteralReplacement", "NegateConditional"]),
            fileValues: [:]
        )

        #expect(result.operators == ["BooleanLiteralReplacement", "NegateConditional"])
    }

    @Test("Given operators only in file as comma-separated, when resolved, then list is split")
    func operatorsFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["operators": "BooleanLiteralReplacement,NegateConditional"]
        )

        #expect(result.operators == ["BooleanLiteralReplacement", "NegateConditional"])
    }

    @Test("Given disabledMutators in file, when resolved, then operators excludes them")
    func disabledMutatorsFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["disabledMutators": "RemoveSideEffects,SwapTernary"]
        )

        #expect(!result.operators.contains("RemoveSideEffects"))
        #expect(!result.operators.contains("SwapTernary"))
        #expect(result.operators.contains("NegateConditional"))
    }

    @Test("Given --disable-mutator via CLI, when resolved, then operators excludes it")
    func disabledMutatorsFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", disabledMutators: ["RemoveSideEffects"]),
            fileValues: [:]
        )

        #expect(!result.operators.contains("RemoveSideEffects"))
        #expect(result.operators.contains("NegateConditional"))
    }

    @Test("Given --operator via CLI and disabledMutators in file, when resolved, then CLI --operator wins")
    func cliOperatorOverridesDisabledMutators() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", operators: ["NegateConditional"]),
            fileValues: ["disabledMutators": "NegateConditional"]
        )

        #expect(result.operators == ["NegateConditional"])
    }

    @Test("Given no operators anywhere, when resolved, then operators defaults to empty array")
    func operatorsDefaultsToEmpty() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.operators.isEmpty)
    }

    @Test("Given concurrency only in file, when resolved, then configuration uses file concurrency")
    func fileConcurrencyUsedWhenCLIOmits() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["concurrency": "8"]
        )

        #expect(result.concurrency == 8)
    }

    @Test("Given explicit project path, when resolved, then path is standardized")
    func explicitProjectPathIsStandardized() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(projectPath: "/tmp/myapp", scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.projectPath.hasSuffix("myapp"))
    }

    @Test("Given empty project path, when resolved, then uses current directory")
    func emptyProjectPathUsesCurrentDirectory() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(projectPath: "", scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(!result.projectPath.isEmpty)
    }

    @Test("Given CLI concurrency, when resolved, then CLI concurrency overrides file")
    func cliConcurrencyOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", concurrency: 2),
            fileValues: ["concurrency": "8"]
        )

        #expect(result.concurrency == 2)
    }

    @Test("Given output path in file, when resolved, then output is set")
    func outputFromFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["output": "/tmp/report.txt"]
        )

        #expect(result.output == "/tmp/report.txt")
    }

    @Test("Given testTarget via CLI, when resolved, then testTarget is set")
    func testTargetFromCLI() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", testTarget: "AppTests"),
            fileValues: [:]
        )

        #expect(result.testTarget == "AppTests")
    }
}
