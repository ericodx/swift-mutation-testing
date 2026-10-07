# Configuration

← [Entry Point](01-entry-point.md) | Next: [Discovery Pipeline →](03-discovery-pipeline.md)

---

## CLI/CommandLineParser.swift

```swift
struct CommandLineParser: Sendable {
    func parse(_ args: [String]) throws -> ParsedArguments
}
```

`--help` (or `-h`) and `--version` as the first word yield `.help` and `.version` at once; `init` yields `.initialize` with an optional project path. Otherwise the first word may be a command — `run` (the default when none is given), `plan`, `merge` or `reproduce` — then the words before the first flag are the command's positionals (the project path for `run` and `plan`; the result files for `merge`; the mutant and an optional project path for `reproduce`), then the flags. Iterates the flags left-to-right, dispatching each token to an internal `applyFlag` method that writes straight into the `ParsedArguments` it returns. Throws `UsageError` for unrecognised flags, for `--shard` outside `run` and for a shard that is not `i/n` — `--shard` is parsed into a `Shard` on the spot, with `PlanError.invalidShard`'s message. For `plan`, `--output` is the plan's path, not a report's. `--project-path <path>` sets the project path of `merge`, whose positionals are the result files, and is refused elsewhere. `--workspace` and `--project` name the Xcode container.

Multi-value flags (`--exclude`, `--operator`, `--disable-mutator`) accumulate into arrays. Boolean flags (`--no-cache`, `--quiet`) set a single Bool. All other flags consume the next token as their value.

---

## CLI/ParsedArguments.swift

```swift
struct ParsedArguments: Sendable {
    enum Command: Sendable, Equatable { case run, plan, merge, reproduce, initialize, help, version }

    var command: Command = .run
    var projectPath: String = "."
    var plan: PlanOptions = PlanOptions()    // path (--plan, or plan's --output), shard: Shard?, results, mutant, projectPath
    var build: BuildOptions = BuildOptions()
    var reporting: ReportingOptions = ReportingOptions()
    var filter: FilterOptions = FilterOptions()
    var gate: GateOptions = GateOptions()

    struct BuildOptions: Sendable {
        var scheme: String?
        var destination: String?
        var testTarget: String?
        var timeout: Double?
        var buildTimeout: Double?
        var concurrency: Int?
        var noCache: Bool = false
        var testingFramework: String?
        var workspace: String?
        var xcodeProject: String?
    }

    struct ReportingOptions: Sendable {
        var outputs: [ReportFormat: String] = [:]
        var keepLogsPath: String?
        var quiet: Bool = false
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String] = []
        var operators: [String] = []
        var disabledMutators: [String] = []
        var operatorTier: String?
    }

    struct GateOptions: Sendable {
        var minScore: Double?
        var baseline: String?
        var maxScoreDrop: Double?
        var maxNewSurvivors: Int?
        var maxIntegrityWarnings: Int?
        var writeBaseline: String?
    }
}
```

| Field | Default | Description |
|---|---|---|
| `command` | `.run` | The first word: `plan`, `merge`, `reproduce`, `init` (`.initialize`), or `--help`/`-h` and `--version` (`.help`, `.version`) |
| `projectPath` | `"."` | First positional argument, or `"."` if absent |
| `plan.shard` | `nil` | `--shard <i/n>`, parsed into a `Shard` |
| `build.scheme` | `nil` | `--scheme <value>` |
| `build.destination` | `nil` | `--destination <value>` |
| `build.testTarget` | `nil` | `--target <value>` |
| `build.testingFramework` | `nil` | `--testing-framework <xctest\|swift-testing>` |
| `build.timeout` | `nil` | `--timeout <seconds>` |
| `build.buildTimeout` | `nil` | `--build-timeout <seconds>` |
| `build.concurrency` | `nil` | `--concurrency <n>` |
| `build.noCache` | `false` | `--no-cache` |
| `build.workspace` | `nil` | `--workspace <path>` |
| `build.xcodeProject` | `nil` | `--project <path>` |
| `reporting.outputs[format]` | none | each `ReportFormat`'s flag: `--output`, `--html-output`, `--sonar-output`, `--sarif-output`, `--markdown-output` `<path>` — read off `ReportFormat.named(flag:)`, so a new format needs no parser case |
| `reporting.keepLogsPath` | `nil` | `--keep-logs <directory>` |
| `reporting.quiet` | `false` | `--quiet` |
| `filter.sourcesPath` | `nil` | `--sources-path <path>` |
| `filter.excludePatterns` | `[]` | `--exclude <pattern>`, repeatable |
| `filter.operators` | `[]` | `--operator <id>`, repeatable |
| `filter.disabledMutators` | `[]` | `--disable-mutator <id>`, repeatable |
| `filter.operatorTier` | `nil` | `--operator-tier <tier>` |
| `gate.minScore` | `nil` | `--min-score <0-100>` |
| `gate.baseline` | `nil` | `--baseline <path>` |
| `gate.maxScoreDrop` | `nil` | `--max-score-drop <points>`, `0` allowed |
| `gate.maxNewSurvivors` | `nil` | `--max-new-survivors <n>` |
| `gate.maxIntegrityWarnings` | `nil` | `--max-integrity-warnings <n>` |
| `gate.writeBaseline` | `nil` | `--write-baseline <path>` |

`CommandLineParser` applies each flag through one function per option group — build, reporting, filter, gate and plan — and reports an unknown option when none of them takes it.

---

## Configuration/RunnerConfiguration.swift

```swift
struct RunnerConfiguration: Sendable {
    let projectPath: String
    let build: BuildOptions
    let reporting: ReportingOptions
    let filter: FilterOptions
    var gate: GateOptions = GateOptions()

    static let defaultXcodeTimeout: Double   // 120.0
    static let defaultSPMTimeout: Double     // 30.0
    static let defaultBuildTimeout: Double   // 120.0
    static let defaultConcurrency: Int       // concurrency(forProcessors: processorCount)
    static func concurrency(forProcessors processorCount: Int) -> Int   // max(1, processorCount - 1)

    struct BuildOptions: Sendable {
        var projectType: ProjectType
        var testTarget: String?
        var timeout: Double
        var concurrency: Int
        var noCache: Bool
        var testingFramework: TestingFramework  // default: .swiftTesting
    }

    struct ReportingOptions: Sendable {
        var outputs: [ReportFormat: String] = [:]  // the CLI path, else the file's `format.fileKey`
        var keepLogsPath: String?
        var quiet: Bool
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String]
        var operators: [String]
    }

    struct GateOptions: Sendable {
        var policy: GatePolicy          // default: no policy
        var baselinePath: String?
        var writeBaselinePath: String?
        var isActive: Bool { get }      // a policy is set, or a baseline is given
    }
}
```

Fully resolved configuration passed to both pipelines. Organized into four nested option groups: build, reporting, filter and gate. `gate` defaults to an inactive gate, so a run without gate settings behaves as it did before the gate existed.

| Constant | Value |
|---|---|
| `defaultXcodeTimeout` | `120.0` |
| `defaultSPMTimeout` | `30.0` |
| `defaultBuildTimeout` | `120.0` |
| `defaultConcurrency` | `concurrency(forProcessors: ProcessInfo.processorCount)`, i.e. `max(1, processorCount - 1)` |

`concurrency(forProcessors:)` takes the processor count as a parameter so a test can check the formula without depending on the machine it runs on.

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

## Configuration/XcodeContainer.swift and Configuration/XcodeContainerLocator.swift

```swift
enum XcodeContainer: Sendable, Equatable {
    case workspace(String)
    case project(String)
    var path: String
    var arguments: [String]   // ["-workspace", path] or ["-project", path]
    var key: String           // "workspace" or "project", for the file and the flags
}

enum XcodeContainerLocator {
    struct Candidates: Sendable, Equatable { let workspaces: [String]; let projects: [String] }
    static func locate(in root: URL, workspace: String?, project: String?, fileSystem: FileSystem = FileSystem()) throws -> XcodeContainer?
    static func candidates(in root: URL, fileSystem: FileSystem = FileSystem()) -> Candidates
    static func nestedCandidates(in root: URL, depth: Int = 3, fileSystem: FileSystem = FileSystem()) -> Candidates
    static func projects(referencedBy workspace: String, in root: URL) -> [String]
}
```

`locate` takes an explicit container after checking it exists under the root with the right extension, else decides from the root — one workspace, else one project — and throws `UsageError` on two of a kind, on both flags at once, on a workspace that references a project outside the root, and on a root with no container whose subdirectories have some (`nestedCandidates`, three levels, bundles, hidden and dependency directories skipped), which it lists as suggestions. `projects(referencedBy:)` reads `contents.xcworkspacedata` with `XMLParser`, resolving `group:`, `container:` and `absolute:` locations through nested groups. Directory listings and existence checks go through the `FileSystem` given, so a test can describe a tree without creating it. The rules are in [Architecture — Configuration](../Architecture/04-configuration.md#xcodecontainer).

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
    static let fileName: String            // ".swift-mutation-testing.yml"
    static let fileKeys: Set<String>
    var fileSystem = FileSystem()
    var warn: @Sendable (String) -> Void = StandardError.write

    func resolve(cliArguments: ParsedArguments, fileValues: [String: String]) throws -> RunnerConfiguration
}
```

Merges `ParsedArguments` (CLI, higher priority) with `[String: String]` from the YAML parser (lower priority). CLI values always win. The project path is made absolute with `fileSystem.projectPath(_:)` (`.` or empty is the current directory), and the `Package.swift` and baseline existence checks go through the same `FileSystem`.

For Xcode projects, throws `UsageError` if `scheme` or `destination` is absent in both sources.

**File values are checked, not dropped.** A value the file gets wrong used to fall back to the default without a word: `timeout: 0` was accepted, `timeout: soon` became the default, `quiet: yes` was false, and a misspelled key did nothing. Now `timeout` and `build-timeout` must be positive numbers and `concurrency` an integer of at least 1 — the same rules as their flags, in an error that names the file rather than the flag — and `quiet` and `no-cache` accept `true`/`yes`/`on` and `false`/`no`/`off` in any case and reject anything else. Every key outside `fileKeys` is reported through `warn` as `Warning: unknown key '<key>' in .swift-mutation-testing.yml is ignored`; it is a warning rather than an error so that a file written for a newer version still runs. SPM projects are auto-detected when a `Package.swift` exists and no `.xcodeproj`/`.xcworkspace` is found.

**Operator resolution** (`resolveOperators`), which always yields the full list of identifiers to run:

1. An explicit list — `--operator` (CLI) or `operators` (file), CLI first — is used as is, whatever the operators' tiers
2. Otherwise the tier is resolved — `--operator-tier`, else `operator-tier`, else `.standard` (`default`); a name that is no tier is a `UsageError` — and `OperatorRegistry.operatorNames(upTo:)` gives its set, minus the identifiers disabled by `--disable-mutator` (CLI), `disabled-mutators` or the `mutators` block with `active: false` (file), both removed together

**Gate resolution** (`resolveGate`): each policy comes from its flag or, failing that, from `min-score`, `max-score-drop`, `max-new-survivors` and `max-integrity-warnings` in the file. `baseline` and `--write-baseline` are resolved against the project path unless absolute. Throws `UsageError` when `min-score` is outside 0–100, a maximum is negative, a file value is not a number, `max-score-drop` or `max-new-survivors` is set without a baseline, or the baseline file does not exist.

---

## Configuration/ConfigurationFileParser.swift

```swift
struct ConfigurationFileParser: Sendable {
    func parse(at projectPath: String) throws -> [String: String]
}
```

Reads `.swift-mutation-testing.yml` from `<projectPath>/.swift-mutation-testing.yml`. Returns an empty dictionary if the file does not exist.

Parses YAML line-by-line. Handles top-level scalar values and a `mutators:` block where each entry can have an `active: false` sub-key. Disabled mutator names are collected under the key `"disabled-mutators"` (comma-separated) in the returned dictionary.

Every line first goes through `strippingComment(_:)`, which cuts it at a `#` that starts the line or follows whitespace, outside single or double quotes — so `timeout: 60 # seconds` reads `60`, while `"My #App"` and `Sources/C#Bridge` keep theirs.

---

## Configuration/ConfigurationFileWriter.swift

```swift
struct ConfigurationFileWriter: Sendable {
    func write(to projectPath: String, project: DetectedProject) throws
}
```

Writes `.swift-mutation-testing.yml` at `<projectPath>/.swift-mutation-testing.yml`. Throws if the file already exists.

Generates YAML content using `DetectedProject` values where available, falling back to placeholder comments. For an Xcode project the detected container comes first, as `workspace:` or `project:`; when none was chosen, the reason and every candidate, commented out. Fixed values in the generated file:

- `timeout: 60` — matches `RunnerConfiguration.defaultTimeout`
- `concurrency` — written as a comment (`# concurrency: 4`); the code default (`max(1, CPU count - 1)`) applies when absent
- quality gate keys — `min-score`, `baseline`, `max-score-drop`, `max-new-survivors` and `max-integrity-warnings`, all commented
- `mutators:` block — one `- name: / active: true` entry per operator from `OperatorRegistry.allOperatorNames`; user sets `active: false` to disable individual operators

---

## Configuration/ProjectDetector.swift

```swift
struct ProjectDetector: Sendable {
    let launcher: any ProcessLaunching
    var fileSystem = FileSystem()
    func detect(at projectPath: String) async -> DetectedProject
    private func detectXcode(at: URL, candidates: XcodeContainerLocator.Candidates) async -> DetectedProject
    private func listProject(container:workingDirectory:) async -> (schemes: [String], projectName: String?, testTarget: String?)
    private func listSPMTestTargets(in: String) async -> [String]
    private func detectDestination(in: URL, container: XcodeContainer?) async -> String
    private func detectTestingFramework(at:testTarget:) -> TestingFramework
    private static let simulatorPlatforms: [SimulatorPlatform]   // sdkroot, platform, device selector
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

`detectDestination` reads the `SDKROOT` of the project the container builds (the project itself, the first one a workspace references, or the first at the root) and walks the `simulatorPlatforms` table — iOS, tvOS, watchOS, visionOS, in that order, each with the `SDKROOT` that names it and how to pick its device. For the first platform whose `SDKROOT` matches and for which `xcrun simctl list devices available --json` has a device, it returns `platform=<platform> Simulator,OS=latest,name=<device>`, searching the newest runtime first. Anything else falls back to `platform=macOS`. Adding a platform is one entry in the table.

The project path (`fileSystem.projectPath(_:)`), the container candidates, the `Package.swift` check and the test-target directory check go through the injected `FileSystem`.

`detectTestingFramework` scans test target source files for `import Testing` (Swift Testing) or `import XCTest` patterns to determine the testing framework in use.

---

## Configuration/DetectedProject.swift

```swift
struct DetectedProject: Sendable {
    let kind: Kind
    let testTarget: String?
    var testingFramework: TestingFramework
    var xcodeContainer: XcodeContainer?          // what init writes as workspace: / project:
    var containerNote: String?                   // why none was chosen
    var containerCandidates: [XcodeContainer]    // written commented out when none was chosen

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
