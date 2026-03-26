import Testing

@testable import SwiftMutationTesting

@Suite("CommandLineParser")
struct CommandLineParserTests {
    private let parser = CommandLineParser()

    @Test(
        "Given run command with path and required flags, when parsed, then projectPath scheme and destination are set")
    func parsesRunWithPathAndFlags() throws {
        let result = try parser.parse(["run", "/my/project", "--scheme", "MyApp", "--destination", "platform=macOS"])

        #expect(result.projectPath == "/my/project")
        #expect(result.scheme == "MyApp")
        #expect(result.destination == "platform=macOS")
        #expect(result.showHelp == false)
        #expect(result.showVersion == false)
    }

    @Test("Given run command without explicit path, when parsed, then projectPath defaults to dot")
    func defaultsProjectPathToDot() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "platform=macOS"])

        #expect(result.projectPath == ".")
    }

    @Test("Given --help flag, when parsed, then showHelp is true")
    func returnsShowHelpForHelpFlag() throws {
        let result = try parser.parse(["--help"])

        #expect(result.showHelp == true)
    }

    @Test("Given -h flag, when parsed, then showHelp is true")
    func returnsShowHelpForShortFlag() throws {
        let result = try parser.parse(["-h"])

        #expect(result.showHelp == true)
    }

    @Test("Given empty arguments, when parsed, then execution is attempted with default project path")
    func attemptsExecutionWhenEmpty() throws {
        let result = try parser.parse([])

        #expect(result.showHelp == false)
        #expect(result.projectPath == ".")
    }

    @Test("Given --version flag, when parsed, then showVersion is true")
    func returnsShowVersion() throws {
        let result = try parser.parse(["--version"])

        #expect(result.showVersion == true)
    }

    @Test("Given --no-cache and --quiet flags, when parsed, then noCache and quiet are true")
    func parsesBooleanFlags() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d", "--no-cache", "--quiet"])

        #expect(result.noCache == true)
        #expect(result.quiet == true)
    }

    @Test("Given optional string flags, when parsed, then all string values are set")
    func parsesOptionalStringFlags() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--target", "AppTests",
            "--output", "out.json",
            "--html-output", "report.html",
            "--sonar-output", "sonar.json",
        ])

        #expect(result.testTarget == "AppTests")
        #expect(result.output == "out.json")
        #expect(result.htmlOutput == "report.html")
        #expect(result.sonarOutput == "sonar.json")
    }

    @Test("Given --timeout and --concurrency flags, when parsed, then numeric values are set")
    func parsesNumericFlags() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--timeout", "90.5",
            "--concurrency", "3",
        ])

        #expect(result.timeout == 90.5)
        #expect(result.concurrency == 3)
    }

    @Test("Given init command without path, when parsed, then showInit is true and projectPath defaults to dot")
    func parsesInitWithDefaultPath() throws {
        let result = try parser.parse(["init"])

        #expect(result.showInit == true)
        #expect(result.projectPath == ".")
    }

    @Test("Given init command with explicit path, when parsed, then showInit is true and projectPath is set")
    func parsesInitWithExplicitPath() throws {
        let result = try parser.parse(["init", "/my/project"])

        #expect(result.showInit == true)
        #expect(result.projectPath == "/my/project")
    }

    @Test("Given flags without run command, when parsed, then projectPath scheme and destination are set")
    func parsesDirectFlagsWithoutRunCommand() throws {
        let result = try parser.parse(["--scheme", "MyApp", "--destination", "platform=macOS"])

        #expect(result.projectPath == ".")
        #expect(result.scheme == "MyApp")
        #expect(result.destination == "platform=macOS")
    }

    @Test("Given project path without run command, when parsed, then projectPath is set")
    func parsesProjectPathWithoutRunCommand() throws {
        let result = try parser.parse(["/my/project", "--scheme", "App", "--destination", "platform=macOS"])

        #expect(result.projectPath == "/my/project")
        #expect(result.scheme == "App")
    }

    @Test("Given an unknown flag, when parsed, then throws UsageError")
    func throwsForUnknownFlag() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--unknown"])
        }
    }

    @Test("Given a flag without its required value, when parsed, then throws UsageError")
    func throwsWhenFlagMissingValue() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--scheme"])
        }
    }

    @Test("Given a non-numeric timeout value, when parsed, then throws UsageError")
    func throwsForInvalidTimeout() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--timeout", "abc"])
        }
    }

    @Test("Given a non-numeric concurrency value, when parsed, then throws UsageError")
    func throwsForInvalidConcurrency() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--concurrency", "abc"])
        }
    }

    @Test("Given --sources-path flag, when parsed, then sourcesPath is set")
    func parsesSourcesPath() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d", "--sources-path", "/my/sources",
        ])

        #expect(result.sourcesPath == "/my/sources")
    }

    @Test("Given repeated --exclude flags, when parsed, then all patterns are collected")
    func parsesMultipleExcludePatterns() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--exclude", "/Generated/",
            "--exclude", "/Pods/",
        ])

        #expect(result.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given repeated --operator flags, when parsed, then all operators are collected")
    func parsesMultipleOperators() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--operator", "BooleanLiteralReplacement",
            "--operator", "NegateConditional",
        ])

        #expect(result.operators == ["BooleanLiteralReplacement", "NegateConditional"])
    }

    @Test("Given no --exclude or --operator flags, when parsed, then defaults are empty arrays")
    func defaultsToEmptyArraysForListFlags() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d"])

        #expect(result.excludePatterns.isEmpty)
        #expect(result.operators.isEmpty)
    }

    @Test("Given repeated --disable-mutator flags, when parsed, then all disabled mutators are collected")
    func disabledMutatorsAreCollected() throws {
        let result = try parser.parse([
            "run",
            "--scheme", "App",
            "--destination", "d",
            "--disable-mutator", "RemoveSideEffects",
            "--disable-mutator", "SwapTernary",
        ])

        #expect(result.disabledMutators == ["RemoveSideEffects", "SwapTernary"])
    }
}
