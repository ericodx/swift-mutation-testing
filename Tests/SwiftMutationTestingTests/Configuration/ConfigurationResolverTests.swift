import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationResolver")
struct ConfigurationResolverTests {
    private let resolver = ConfigurationResolver()

    @Test("uses CLI scheme and destination")
    func usesCLIValues() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "MyApp", destination: "platform=macOS"),
            fileValues: [:]
        )

        #expect(result.scheme == "MyApp")
        #expect(result.destination == "platform=macOS")
    }

    @Test("falls back to file values when CLI omits scheme and destination")
    func fallsBackToFileValues() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(),
            fileValues: ["scheme": "FileApp", "destination": "platform=macOS"]
        )

        #expect(result.scheme == "FileApp")
        #expect(result.destination == "platform=macOS")
    }

    @Test("CLI scheme overrides file scheme")
    func cliSchemeOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "CLIApp", destination: "platform=macOS"),
            fileValues: ["scheme": "FileApp"]
        )

        #expect(result.scheme == "CLIApp")
    }

    @Test("file timeout used when CLI omits it")
    func fileTimeoutUsedWhenCLIOmits() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: ["timeout": "120"]
        )

        #expect(result.timeout == 120)
    }

    @Test("CLI timeout overrides file timeout")
    func cliTimeoutOverridesFile() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d", timeout: 30),
            fileValues: ["timeout": "120"]
        )

        #expect(result.timeout == 30)
    }

    @Test("applies default timeout when neither CLI nor file provides one")
    func appliesDefaultTimeout() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.timeout == RunnerConfiguration.defaultTimeout)
    }

    @Test("applies default concurrency when neither CLI nor file provides one")
    func appliesDefaultConcurrency() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(scheme: "App", destination: "d"),
            fileValues: [:]
        )

        #expect(result.concurrency == RunnerConfiguration.defaultConcurrency)
    }

    @Test("throws when scheme is missing in standalone mode")
    func throwsWhenSchemeMissing() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(destination: "platform=macOS"),
                fileValues: [:]
            )
        }
    }

    @Test("throws when destination is missing in standalone mode")
    func throwsWhenDestinationMissing() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(scheme: "MyApp"),
                fileValues: [:]
            )
        }
    }

    @Test("skips scheme and destination validation in integration mode")
    func skipsValidationInIntegrationMode() throws {
        let result = try resolver.resolve(
            cliArguments: ParsedArguments(input: "runner-input.json"),
            fileValues: [:]
        )

        #expect(result.projectPath == ".")
    }

    @Test("throws when concurrency is less than one")
    func throwsWhenConcurrencyLessThanOne() {
        #expect(throws: UsageError.self) {
            try resolver.resolve(
                cliArguments: ParsedArguments(scheme: "App", destination: "d", concurrency: 0),
                fileValues: [:]
            )
        }
    }
}
