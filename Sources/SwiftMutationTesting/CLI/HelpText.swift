enum HelpText {
    static let usage = """
        USAGE: swift-mutation-testing <command> [<project-path>] [options]

        COMMANDS:
          run                           Run mutation testing
          init                          Generate a .swift-mutation-testing.yml config file

        ARGUMENTS:
          <project-path>                Path to the Xcode project root (default: .)

        OPTIONS:
          --scheme <scheme>             Xcode scheme to build and test (required)
          --destination <destination>   xcodebuild destination specifier (required)
          --target <test-target>        Test target name
          --timeout <seconds>           Per-mutant test timeout in seconds (default: 60)
          --concurrency <n>             Number of parallel test workers (default: CPUs - 1)
          --no-cache                    Disable the result cache
          --output <json-path>          Write Stryker-compatible JSON report to path
          --html-output <html-path>     Write HTML report to path
          --sonar-output <json-path>    Write Sonar Generic Coverage report to path
          --quiet                       Suppress progress output
          --input <json-path>           Load RunnerInput from JSON (SMT integration mode)
          --version                     Print version and exit
          --help                        Print this help and exit
        """
}
