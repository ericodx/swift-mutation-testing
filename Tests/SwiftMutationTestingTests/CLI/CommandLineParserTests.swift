import Testing

@testable import SwiftMutationTesting

@Suite("CommandLineParser")
struct CommandLineParserTests {
    private let parser = CommandLineParser()

    @Test("parses run command with path and required flags")
    func parsesRunWithPathAndFlags() throws {
        let result = try parser.parse(["run", "/my/project", "--scheme", "MyApp", "--destination", "platform=macOS"])

        #expect(result.projectPath == "/my/project")
        #expect(result.scheme == "MyApp")
        #expect(result.destination == "platform=macOS")
        #expect(!result.showHelp)
        #expect(!result.showVersion)
    }

    @Test("defaults project path to dot when omitted after run")
    func defaultsProjectPathToDot() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "platform=macOS"])

        #expect(result.projectPath == ".")
    }

    @Test("returns showHelp for --help")
    func returnsShowHelpForHelpFlag() throws {
        #expect(try parser.parse(["--help"]).showHelp)
    }

    @Test("returns showHelp for -h")
    func returnsShowHelpForShortFlag() throws {
        #expect(try parser.parse(["-h"]).showHelp)
    }

    @Test("returns showHelp when arguments are empty")
    func returnsShowHelpWhenEmpty() throws {
        #expect(try parser.parse([]).showHelp)
    }

    @Test("returns showVersion for --version")
    func returnsShowVersion() throws {
        #expect(try parser.parse(["--version"]).showVersion)
    }

    @Test("parses boolean flags")
    func parsesBooleanFlags() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d", "--no-cache", "--quiet"])

        #expect(result.noCache)
        #expect(result.quiet)
    }

    @Test("parses optional string flags")
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

    @Test("parses numeric flags")
    func parsesNumericFlags() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--timeout", "90.5",
            "--concurrency", "3",
        ])

        #expect(result.timeout == 90.5)
        #expect(result.concurrency == 3)
    }

    @Test("throws for unknown flag")
    func throwsForUnknownFlag() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--unknown"])
        }
    }

    @Test("throws when flag is missing its value")
    func throwsWhenFlagMissingValue() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--scheme"])
        }
    }

    @Test("throws for invalid timeout")
    func throwsForInvalidTimeout() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--timeout", "abc"])
        }
    }

    @Test("throws for invalid concurrency")
    func throwsForInvalidConcurrency() {
        #expect(throws: UsageError.self) {
            try parser.parse(["run", "--concurrency", "abc"])
        }
    }
}
