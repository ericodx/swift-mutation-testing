enum HelpText {
    static let usage = """
        USAGE: swift-mutation-testing [<project-path>] [options]
               swift-mutation-testing init [<project-path>]

        COMMANDS:
          init                          Generate a .swift-mutation-testing.yml config file

        ARGUMENTS:
          <project-path>                Path to the Xcode project root (default: .)

        OPTIONS:
          --scheme <scheme>             Xcode scheme to build and test (Xcode projects only)
          --destination <destination>   xcodebuild destination specifier (Xcode projects only)
          --testing-framework <fw>       Testing framework: xctest or swift-testing (default: swift-testing)
          --target <test-target>        Test target name
          --timeout <seconds>           Per-mutant test timeout in seconds (default: 120 Xcode, 30 SPM)
          --concurrency <n>             Number of parallel test workers (default: CPUs - 1)
          --no-cache                    Disable the result cache
          --output <json-path>          Write mutation report JSON to path
          --html-output <html-path>     Write HTML report to path
          --sonar-output <json-path>    Write Sonar Generic Coverage report to path
          --quiet                       Suppress progress output
          --sources-path <path>         Root directory to discover Swift source files (default: project path)
          --exclude <pattern>           Exclude files matching pattern (repeatable)
          --operator <id>               Mutation operator to apply (repeatable, default: all)
          --disable-mutator <id>        Disable a specific mutation operator (repeatable)
          --version                     Print version and exit
          --help                        Print this help and exit
        """
}
