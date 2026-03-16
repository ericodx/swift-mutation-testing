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

    @Test("Given empty arguments, when parsed, then showHelp is true")
    func returnsShowHelpWhenEmpty() throws {
        let result = try parser.parse([])

        #expect(result.showHelp == true)
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
            "--input", "input.json",
        ])

        #expect(result.testTarget == "AppTests")
        #expect(result.output == "out.json")
        #expect(result.htmlOutput == "report.html")
        #expect(result.sonarOutput == "sonar.json")
        #expect(result.input == "input.json")
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
}
