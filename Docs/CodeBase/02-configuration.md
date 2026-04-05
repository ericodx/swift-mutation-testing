# Configuration

← [Entry Point](01-entry-point.md) | Next: [Discovery Pipeline →](03-discovery-pipeline.md)

---

## CLI/CommandLineParser.swift

```swift
struct CommandLineParser: Sendable {
    func parse(_ args: [String]) throws -> ParsedArguments
}
```

Iterates `args` left-to-right, dispatching each token to an internal `applyFlag` method. Stores intermediate state in a private `FlagValues` struct. Throws `UsageError` for unrecognised flags.

Multi-value flags (`--exclude`, `--operator`, `--disable-mutator`) accumulate into arrays. Boolean flags (`--no-cache`, `--help`, `--version`, `init`, `--quiet`) set a single Bool. All other flags consume the next token as their value.

---

## CLI/ParsedArguments.swift

```swift
struct ParsedArguments: Sendable {
    let projectPath: String
    var showHelp: Bool
    var showVersion: Bool
    var showInit: Bool
    var scheme: String?
    var destination: String?
    var testTarget: String?
    var timeout: Double?
    var concurrency: Int?
    var noCache: Bool
    var output: String?
    var htmlOutput: String?
    var sonarOutput: String?
    var sourcesPath: String?
    var excludePatterns: [String]
    var operators: [String]
    var disabledMutators: [String]
    var quiet: Bool
}
```

| Field | Default | Description |
|---|---|---|
| `projectPath` | `"."` | First positional argument, or `"."` if absent |
| `showHelp` | `false` | Set by `--help` |
| `showVersion` | `false` | Set by `--version` |
| `showInit` | `false` | Set by the `init` subcommand |
| `scheme` | `nil` | `--scheme <value>` |
| `destination` | `nil` | `--destination <value>` |
| `testTarget` | `nil` | `--target <value>` |
| `timeout` | `nil` | `--timeout <seconds>` |
| `concurrency` | `nil` | `--concurrency <n>` |
| `noCache` | `false` | `--no-cache` |
| `output` | `nil` | `--output <path>` |
| `htmlOutput` | `nil` | `--html-output <path>` |
| `sonarOutput` | `nil` | `--sonar-output <path>` |
| `sourcesPath` | `nil` | `--sources-path <path>` |
| `excludePatterns` | `[]` | `--exclude <pattern>`, repeatable |
| `operators` | `[]` | `--operator <id>`, repeatable |
| `disabledMutators` | `[]` | `--disable-mutator <id>`, repeatable |
| `quiet` | `false` | `--quiet` |

---

## Configuration/RunnerConfiguration.swift

```swift
struct RunnerConfiguration: Sendable {
    let projectPath: String
    let build: BuildOptions
    let reporting: ReportingOptions
    let filter: FilterOptions

    static let defaultXcodeTimeout: Double   // 120.0
    static let defaultSPMTimeout: Double     // 30.0
    static let defaultConcurrency: Int       // max(1, processorCount - 1)

    struct BuildOptions: Sendable {
        var projectType: ProjectType
        var testTarget: String?
        var timeout: Double
        var concurrency: Int
        var noCache: Bool
        var testingFramework: TestingFramework  // default: .swiftTesting
    }

    struct ReportingOptions: Sendable {
        var output: String?
        var htmlOutput: String?
        var sonarOutput: String?
        var quiet: Bool
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String]
        var operators: [String]
    }
}
```

Fully resolved configuration passed to both pipelines. Organized into three nested option groups: build, reporting, and filter.

| Constant | Value |
|---|---|
| `defaultXcodeTimeout` | `120.0` |
| `defaultSPMTimeout` | `30.0` |
| `defaultConcurrency` | `max(1, ProcessInfo.processorCount - 1)` |

---

## Configuration/ProjectType.swift

```swift
enum ProjectType: Sendable, Equatable {
    case xcode(scheme: String, destination: String)
    case spm
}
```

Xcode projects carry a scheme and destination. SPM projects require neither — `swift build` and `swift test` use the `Package.swift` manifest directly.

---

## Configuration/TestingFramework.swift

```swift
enum TestingFramework: String, Sendable {
    case xctest
    case swiftTesting = "swift-testing"
}
```

Detected automatically by `ProjectDetector` via source file scanning. Influences test output parsing patterns.

---

## Configuration/ConfigurationResolver.swift

```swift
struct ConfigurationResolver: Sendable {
    func resolve(cliArguments: ParsedArguments, fileValues: [String: String]) throws -> RunnerConfiguration
}
```

Merges `ParsedArguments` (CLI, higher priority) with `[String: String]` from the YAML parser (lower priority). CLI values always win.

For Xcode projects, throws `UsageError` if `scheme` or `destination` is absent in both sources. SPM projects are auto-detected when a `Package.swift` exists and no `.xcodeproj`/`.xcworkspace` is found.

**Operator resolution** (`resolveOperators`):

1. If `--operator` flags were passed, use only those identifiers
2. Otherwise start from all operators, then remove any disabled via `--disable-mutator` (CLI) or `mutators` block with `active: false` (file)

---

## Configuration/ConfigurationFileParser.swift

```swift
struct ConfigurationFileParser: Sendable {
    func parse(at projectPath: String) throws -> [String: String]
}
```

Reads `.swift-mutation-testing.yml` from `<projectPath>/.swift-mutation-testing.yml`. Returns an empty dictionary if the file does not exist.

Parses YAML line-by-line. Handles top-level scalar values and a `mutators:` block where each entry can have an `active: false` sub-key. Disabled mutator names are collected under the key `"disabledMutators"` (comma-separated) in the returned dictionary.

---

## Configuration/ConfigurationFileWriter.swift

```swift
struct ConfigurationFileWriter: Sendable {
    func write(to projectPath: String, project: DetectedProject) throws
}
```

Writes `.swift-mutation-testing.yml` at `<projectPath>/.swift-mutation-testing.yml`. Throws if the file already exists.

Generates YAML content using `DetectedProject` values where available, falling back to placeholder comments. Fixed values in the generated file:

- `timeout: 60` — matches `RunnerConfiguration.defaultTimeout`
- `concurrency` — written as a comment (`# concurrency: 4`); the code default (`max(1, CPU count - 1)`) applies when absent
- `mutators:` block — one `- name: / active: true` entry per operator from `DiscoveryPipeline.allOperatorNames`; user sets `active: false` to disable individual operators

---

## Configuration/ProjectDetector.swift

```swift
struct ProjectDetector: Sendable {
    init(launcher: any ProcessLaunching)
    func detect(at projectPath: String) async -> DetectedProject
    private func findContainer(in: String) -> (flag: String, path: String)?
    private func listProject(container:workingDirectory:) async -> (schemes: [String], projectName: String?, testTarget: String?)
    private func listSPMTestTargets(in: String) async -> [String]
    private func detectDestination(in: String) async -> String
    private func detectTestingFramework(at:testTarget:) -> TestingFramework
}
```

Auto-detects the project type, scheme, test targets, destination, and testing framework.

```mermaid
flowchart TD
    A[detect at projectPath] --> B{.xcworkspace or\n.xcodeproj found?}
    B -- yes --> C[xcodebuild -list -json]
    C --> D[DetectedProject.xcode\nscheme · testTarget · destination]
    B -- no --> E{Package.swift found?}
    E -- yes --> F[swift package dump-package]
    F --> G[DetectedProject.spm\ntestTargets]
    E -- no --> H[DetectedProject with nil fields]
    D --> I[detectDestination\niOS/tvOS/watchOS/visionOS/macOS]
    I --> J[detectTestingFramework\nXCTest or Swift Testing]
    G --> J
    J --> K[DetectedProject]
```

`detectDestination` queries `xcrun simctl list devices --json` and picks the first booted or available simulator for the detected platform. Falls back to hardcoded default destinations if detection fails.

`detectTestingFramework` scans test target source files for `import Testing` (Swift Testing) or `import XCTest` patterns to determine the testing framework in use.

---

## Configuration/DetectedProject.swift

```swift
struct DetectedProject: Sendable {
    let kind: Kind
    let testTarget: String?
    let testingFramework: TestingFramework

    enum Kind: Sendable {
        case xcode(scheme: String?, allSchemes: [String], destination: String)
        case spm(testTargets: [String])
    }
}
```

| Field | Description |
|---|---|
| `kind` | `.xcode` with scheme, allSchemes, destination; or `.spm` with testTargets |
| `testTarget` | First test target found, or `nil` |
| `testingFramework` | Detected framework (`.xctest` or `.swiftTesting`) |

Computed properties `scheme`, `allSchemes`, and `destination` extract values from `.xcode` kind for convenience.

---

← [Entry Point](01-entry-point.md) | Next: [Discovery Pipeline →](03-discovery-pipeline.md)
