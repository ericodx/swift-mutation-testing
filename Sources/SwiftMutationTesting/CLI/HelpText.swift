enum HelpText {
    static let usage = """
        USAGE: swift-mutation-testing [run] [<project-path>] [options]
               swift-mutation-testing init [<project-path>]
               swift-mutation-testing plan [<project-path>] --output <plan.json> [options]
               swift-mutation-testing run [<project-path>] --plan <plan.json> [--shard <i/n>] [options]
               swift-mutation-testing merge <result.json>... --plan <plan.json> [--project-path <path>] [options]
               swift-mutation-testing reproduce <mutant> [<project-path>] [--plan <plan.json>] [options]

        COMMANDS:
          run                           Discover and test every mutant (the default when no command is given)
          init                          Generate a .swift-mutation-testing.yml config file
          plan                          Discover the mutants and write them to a plan, without building
          merge                         Join the results of a plan's shards into one report
          reproduce                     Run one mutant, by fingerprint or id, keep its sandbox and show everything

        PLANS:
          --plan <plan.json>            Run (or merge, or reproduce) from this plan instead of discovering;
                                        the run refuses a plan whose files changed since it was made
          --shard <i/n>                 Run the i-th of n slices of the plan, split by file (run only)
          --project-path <path>         The project a merge reports on (merge only; default: .)

        ARGUMENTS:
          <project-path>                Path to the Xcode project root (default: .)

        OPTIONS:
          --scheme <scheme>             Xcode scheme to build and test (Xcode projects only)
          --destination <destination>   xcodebuild destination specifier (Xcode projects only)
          --workspace <path>            The .xcworkspace to build, relative to the project (Xcode only)
          --project <path>              The .xcodeproj to build, relative to the project (Xcode only).
                                        Without either, the one container at the root; two are an error
          --testing-framework <fw>       Testing framework: xctest or swift-testing (default: swift-testing)
          --target <test-target>        Test target name
          --timeout <seconds>           Per-mutant test timeout in seconds (default: 120 Xcode, 30 SPM)
          --build-timeout <seconds>     Build timeout in seconds (default: 120)
          --concurrency <n>             Parallel test workers (default: CPUs - 1). An Xcode
                                        run on macOS or with XCTest uses one worker
          --no-cache                    Disable the result cache — nothing is read or written
          \(ReportFormat.allCases.map(\.helpLine).joined(separator: "\n  "))
          --keep-logs <directory>       Write each mutant's captured test output to <directory>
          --quiet                       Suppress progress output
          --sources-path <path>         Root directory to discover Swift source files (default: project path)
          --exclude <pattern>           Leave out files matching a glob (**/Generated/**) or containing a
                                        path fragment (/Generated/) (repeatable)
          --operator-tier <tier>        Run the operators up to this tier: conservative, default or
                                        experimental (default: default)
          --operator <id>               Run only this operator, whatever its tier (repeatable)
          --disable-mutator <id>        Leave this operator out of the tier's set (repeatable)
          --version                     Print version and exit
          --help                        Print this help and exit

        QUALITY GATE (a failed gate exits with code 2):
          --min-score <0-100>           Fail when the mutation score is below this
          --baseline <path>             Baseline to compare with, relative to the project
          --max-score-drop <points>     Fail when the score drops more than this below the baseline's
          --max-new-survivors <n>       Fail when more than n undetected mutants are not in the baseline
          --max-integrity-warnings <n>  Fail when more than n mutants were killed or timed out without
                                        the mutated code running
          --write-baseline <path>       Write this run's baseline, relative to the project
        """
}
