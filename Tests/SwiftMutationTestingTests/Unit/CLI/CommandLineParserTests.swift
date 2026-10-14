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
        #expect(result.build.scheme == "MyApp")
        #expect(result.build.destination == "platform=macOS")
        #expect(result.command == .run)
    }

    @Test("Given run command without explicit path, when parsed, then projectPath defaults to dot")
    func defaultsProjectPathToDot() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "platform=macOS"])

        #expect(result.projectPath == ".")
    }

    @Test("Given no command, when parsed, then the command is run")
    func noCommandIsRun() throws {
        #expect(try parser.parse(["--quiet"]).command == .run)
        #expect(try parser.parse(["run", "."]).command == .run)
        #expect(try parser.parse([]).command == .run)
    }

    @Test("Given the plan command, when parsed, then --output is the plan's path and the project path follows")
    func planCommand() throws {
        let result = try parser.parse(
            ["plan", "/my/project", "--output", "plans/p.json", "--operator-tier", "experimental"]
        )

        #expect(result.command == .plan)
        #expect(result.projectPath == "/my/project")
        #expect(result.plan.path == "plans/p.json")
        #expect(result.reporting.outputs[.json] == nil)
        #expect(result.filter.operatorTier == "experimental")
    }

    @Test("Given run with --plan and --shard, when parsed, then both are kept")
    func runWithPlanAndShard() throws {
        let result = try parser.parse(["run", "--plan", "p.json", "--shard", "2/4", "--output", "r.json"])

        #expect(result.command == .run)
        #expect(result.plan.path == "p.json")
        #expect(result.plan.shard == Shard(parsing: "2/4"))
        #expect(result.reporting.outputs[.json] == "r.json")
    }

    @Test("Given a shard that is not i/n, when parsed, then it is a usage error")
    func aBadShardIsRefused() {
        for raw in ["0/2", "3/2", "x"] {
            #expect(throws: UsageError.self) { try parser.parse(["run", "--shard", raw]) }
        }
        #expect(throws: UsageError.self) { try parser.parse(["plan", "--shard", "1/2"]) }
    }

    @Test("Given the merge command, when parsed, then the positionals are the results and --plan is kept")
    func mergeCommand() throws {
        let result = try parser.parse(["merge", "a.json", "b.json", "--plan", "p.json", "--output", "m.json"])

        #expect(result.command == .merge)
        #expect(result.plan.results == ["a.json", "b.json"])
        #expect(result.plan.path == "p.json")
        #expect(result.reporting.outputs[.json] == "m.json")
        #expect(throws: UsageError.self) { try parser.parse(["merge", "--plan", "p.json"]) }
    }

    @Test("Given merge with --project-path, when parsed, then it is the project path; elsewhere it is refused")
    func mergeTakesAProject() throws {
        let result = try parser.parse(["merge", "a.json", "--plan", "p.json", "--project-path", "/my/project"])

        #expect(result.projectPath == "/my/project")
        #expect(result.plan.results == ["a.json"])
        #expect(try parser.parse(["merge", "a.json", "--plan", "p.json"]).projectPath == ".")
        #expect(throws: UsageError.self) { try parser.parse(["run", "--project-path", "/my/project"]) }
        #expect(throws: UsageError.self) { try parser.parse(["plan", "--project-path", "/my/project"]) }
    }

    @Test("Given the reproduce command, when parsed, then the mutant and the project path are read")
    func reproduceCommand() throws {
        let result = try parser.parse(["reproduce", "3f2a", "/my/project", "--plan", "p.json"])

        #expect(result.command == .reproduce)
        #expect(result.plan.mutant == "3f2a")
        #expect(result.projectPath == "/my/project")
        #expect(result.plan.path == "p.json")
        #expect(try parser.parse(["reproduce", "swift-mutation-testing_12"]).projectPath == ".")
        #expect(throws: UsageError.self) { try parser.parse(["reproduce"]) }
    }

    @Test("Given --help flag, when parsed, then the command is help")
    func returnsShowHelpForHelpFlag() throws {
        let result = try parser.parse(["--help"])

        #expect(result.command == .help)
    }

    @Test("Given -h flag, when parsed, then the command is help")
    func returnsShowHelpForShortFlag() throws {
        let result = try parser.parse(["-h"])

        #expect(result.command == .help)
    }

    @Test("Given empty arguments, when parsed, then execution is attempted with default project path")
    func attemptsExecutionWhenEmpty() throws {
        let result = try parser.parse([])

        #expect(result.command == .run)
        #expect(result.projectPath == ".")
    }

    @Test("Given --version flag, when parsed, then the command is version")
    func returnsShowVersion() throws {
        let result = try parser.parse(["--version"])

        #expect(result.command == .version)
    }

    @Test("Given --build-timeout, when parsed, then it is separate from --timeout")
    func parsesBuildTimeoutSeparatelyFromTimeout() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--timeout", "30",
            "--build-timeout", "240",
        ])

        #expect(result.build.timeout == 30)
        #expect(result.build.buildTimeout == 240)
    }

    @Test("Given --no-cache and --quiet flags, when parsed, then noCache and quiet are true")
    func parsesBooleanFlags() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d", "--no-cache", "--quiet"])

        #expect(result.build.noCache)
        #expect(result.reporting.quiet)
    }

    @Test("Given optional string flags, when parsed, then all string values are set")
    func parsesOptionalStringFlags() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--target", "AppTests",
            "--output", "out.json",
            "--html-output", "report.html",
            "--sonar-output", "sonar.json",
            "--sarif-output", "report.sarif",
            "--markdown-output", "summary.md",
            "--keep-logs", "logs",
        ])

        #expect(result.build.testTarget == "AppTests")
        #expect(result.reporting.outputs[.json] == "out.json")
        #expect(result.reporting.outputs[.html] == "report.html")
        #expect(result.reporting.outputs[.sonar] == "sonar.json")
        #expect(result.reporting.outputs[.sarif] == "report.sarif")
        #expect(result.reporting.outputs[.markdown] == "summary.md")
        #expect(result.reporting.keepLogsPath == "logs")
    }

    @Test("Given --timeout and --concurrency flags, when parsed, then numeric values are set")
    func parsesNumericFlags() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--timeout", "90.5",
            "--concurrency", "3",
        ])

        #expect(result.build.timeout == 90.5)
        #expect(result.build.concurrency == 3)
    }

    @Test("Given init command without path, when parsed, then the command is init and projectPath defaults to dot")
    func parsesInitWithDefaultPath() throws {
        let result = try parser.parse(["init"])

        #expect(result.command == .initialize)
        #expect(result.projectPath == ".")
    }

    @Test("Given init command with explicit path, when parsed, then the command is init and projectPath is set")
    func parsesInitWithExplicitPath() throws {
        let result = try parser.parse(["init", "/my/project"])

        #expect(result.command == .initialize)
        #expect(result.projectPath == "/my/project")
    }

    @Test("Given flags without run command, when parsed, then projectPath scheme and destination are set")
    func parsesDirectFlagsWithoutRunCommand() throws {
        let result = try parser.parse(["--scheme", "MyApp", "--destination", "platform=macOS"])

        #expect(result.projectPath == ".")
        #expect(result.build.scheme == "MyApp")
        #expect(result.build.destination == "platform=macOS")
    }

    @Test("Given project path without run command, when parsed, then projectPath is set")
    func parsesProjectPathWithoutRunCommand() throws {
        let result = try parser.parse(["/my/project", "--scheme", "App", "--destination", "platform=macOS"])

        #expect(result.projectPath == "/my/project")
        #expect(result.build.scheme == "App")
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

        #expect(result.filter.sourcesPath == "/my/sources")
    }

    @Test("Given repeated --exclude flags, when parsed, then all patterns are collected")
    func parsesMultipleExcludePatterns() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--exclude", "/Generated/",
            "--exclude", "/Pods/",
        ])

        #expect(result.filter.excludePatterns == ["/Generated/", "/Pods/"])
    }

    @Test("Given repeated --operator flags, when parsed, then all operators are collected")
    func parsesMultipleOperators() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--operator", "BooleanLiteralReplacement",
            "--operator", "NegateConditional",
        ])

        #expect(result.filter.operators == ["BooleanLiteralReplacement", "NegateConditional"])
    }

    @Test("Given no --exclude or --operator flags, when parsed, then defaults are empty arrays")
    func defaultsToEmptyArraysForListFlags() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d"])

        #expect(result.filter.excludePatterns.isEmpty)
        #expect(result.filter.operators.isEmpty)
    }

    @Test("Given --operator-tier conservative, when parsed, then operatorTier is conservative")
    func parsesOperatorTier() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--operator-tier", "conservative",
        ])

        #expect(result.filter.operatorTier == "conservative")
    }

    @Test("Given no --operator-tier flag, when parsed, then operatorTier is nil")
    func operatorTierDefaultsToNil() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d"])

        #expect(result.filter.operatorTier == nil)
    }

    @Test("Given --testing-framework xctest, when parsed, then testingFramework is xctest")
    func parsesTestingFrameworkXCTest() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--testing-framework", "xctest",
        ])

        #expect(result.build.testingFramework == "xctest")
    }

    @Test("Given --testing-framework swift-testing, when parsed, then testingFramework is swift-testing")
    func parsesTestingFrameworkSwiftTesting() throws {
        let result = try parser.parse([
            "run", "--scheme", "App", "--destination", "d",
            "--testing-framework", "swift-testing",
        ])

        #expect(result.build.testingFramework == "swift-testing")
    }

    @Test("Given no --testing-framework flag, when parsed, then testingFramework is nil")
    func testingFrameworkDefaultsToNil() throws {
        let result = try parser.parse(["run", "--scheme", "App", "--destination", "d"])

        #expect(result.build.testingFramework == nil)
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

        #expect(result.filter.disabledMutators == ["RemoveSideEffects", "SwapTernary"])
    }

    @Test("Given --workspace or --project, when parsed, then each is kept as the Xcode container")
    func containerFlags() throws {
        #expect(try parser.parse(["--workspace", "Apps/App.xcworkspace"]).build.workspace == "Apps/App.xcworkspace")
        #expect(try parser.parse(["--project", "App.xcodeproj"]).build.xcodeProject == "App.xcodeproj")
        #expect(try parser.parse(["plan", "--project", "App.xcodeproj"]).build.xcodeProject == "App.xcodeproj")
    }

    @Test("Given --xcodebuild-arg twice, when parsed, then both values are kept in order, dashes and all")
    func xcodebuildArgumentFlags() throws {
        let parsed = try parser.parse(["--xcodebuild-arg", "-allowProvisioningUpdates", "--xcodebuild-arg", "A=B"])

        #expect(parsed.build.xcodebuildArguments == ["-allowProvisioningUpdates", "A=B"])
    }

    @Test("Given --xcodebuild-arg without a value, when parsed, then it is a usage error")
    func xcodebuildArgumentNeedsAValue() {
        #expect(throws: UsageError(message: "--xcodebuild-arg requires a value")) {
            try parser.parse(["--xcodebuild-arg"])
        }
    }
}
