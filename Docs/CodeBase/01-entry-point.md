# Entry Point

← [Index](README.md) | Next: [Configuration →](02-configuration.md)

---

## SwiftMutationTesting.swift

```swift
@main
struct SwiftMutationTesting {
    static func main() async
    static func run(args: [String], launcher: any ProcessLaunching = ProcessLauncher()) async -> ExitCode
    private static func execute(args: [String], launcher: any ProcessLaunching) async throws -> ExitCode
    private static func discover(configuration: RunnerConfiguration) async throws -> RunnerInput
    static func writeReports(_ summary: RunnerSummary, configuration: RunnerConfiguration)
}
```

The program entry point. `main()` drops `CommandLine.arguments[0]` (the executable name) and delegates to `run(args:launcher:)`.

`run` catches three error categories before returning an exit code:
- `UsageError` — prints `message` to stderr
- `SimulatorError.deviceNotFound` — prints destination string to stderr
- Any other `Error` — prints `localizedDescription` to stderr

`execute` is the primary execution path:

```mermaid
flowchart TD
    A[parse CLI args] --> B{showHelp?}
    B -- yes --> HELP[print HelpText.usage → .success]
    B -- no --> C{showVersion?}
    C -- yes --> VER[print 0.1.0 → .success]
    C -- no --> D{showInit?}
    D -- yes --> INIT[ProjectDetector.detect\nConfigurationFileWriter.write → .success]
    D -- no --> E[ConfigurationFileParser.parse\nConfigurationResolver.resolve]
    E --> F[discover → RunnerInput]
    F --> G[MutantExecutor.execute → results]
    G --> H[RunnerSummary]
    H --> I[TextReporter.report]
    I --> J[writeReports → .success]
```

`discover` runs `DiscoveryPipeline` and, when `quiet` is false, emits `.discoveryFinished` to a `ConsoleProgressReporter`.

`writeReports` writes `JsonReporter`, `HtmlReporter`, and `SonarReporter` outputs when the corresponding output path is configured. Each reporter failure prints a warning to stderr without aborting.

---

## CLI/ExitCode.swift

```swift
enum ExitCode: Int32 {
    case success = 0
    case error   = 1
}
```

Passed directly to `exit(_:)` as `rawValue`. All error conditions (usage, build, unexpected) map to `.error`.

---

## CLI/HelpText.swift

```swift
enum HelpText {
    static let usage: String
}
```

A static multi-line string printed when `--help` is passed. Describes all CLI options and subcommands. Not reproduced here — see the source file.

---

## CLI/UsageError.swift

```swift
struct UsageError: Error, Sendable {
    let message: String
}
```

Thrown by `CommandLineParser` for unknown flags and by `ConfigurationResolver` when required fields (`scheme`, `destination`) are absent in both CLI and file values.

| Field | Type | Description |
|---|---|---|
| `message` | `String` | Human-readable description printed to stderr |

---

← [Index](README.md) | Next: [Configuration →](02-configuration.md)
