# Reporting & Infrastructure

← [Result Parsing & Cache](08-result-parsing-cache.md) | [Index →](README.md)

---

## Reporting/ProgressReporter.swift

```swift
protocol ProgressReporter: Sendable {
    func report(_ event: RunnerEvent) async
}
```

Adopted by `ConsoleProgressReporter` and `SilentProgressReporter`. The async requirement allows actor-isolated implementations without `nonisolated` boilerplate.

---

## Reporting/ConsoleProgressReporter.swift

```swift
actor ConsoleProgressReporter: ProgressReporter {
    func report(_ event: RunnerEvent) async
}
```

Serialises progress output to stdout. Each `RunnerEvent` case maps to a formatted `print` call. `.mutantStarted`, `.fallbackBuildStarted`, and `.fallbackBuildFinished` are no-ops (no output).

**Output per event:**

| Event | Output |
|---|---|
| `.discoveryFinished` | `✓ Discovery: N mutants (M schematizable[, K incompatible]) in X.Xs` |
| `.loadedFromCache` | `✓ Loaded N mutants from cache` |
| `.buildStarted` | blank line + `Building for testing...` |
| `.buildFinished` | `✓ Built in X.Xs` |
| `.simulatorPoolReady` | `✓ N simulators ready` + blank line + `Testing mutants...` |
| `.mutantFinished` | `<icon> <index>/<total>  <operator>  <filename>:<line>` |

Progress icon is provided by `ExecutionStatus.progressIcon`.

---

## Reporting/SilentProgressReporter.swift

```swift
struct SilentProgressReporter: Sendable, ProgressReporter {
    func report(_ event: RunnerEvent) async {}
}
```

No-op reporter. Used when `--quiet` is active.

---

## Reporting/RunnerEvent.swift

```swift
enum RunnerEvent: Sendable {
    case discoveryFinished(mutantCount: Int, schematizableCount: Int, incompatibleCount: Int, duration: Double)
    case loadedFromCache(mutantCount: Int)
    case buildStarted
    case buildFinished(duration: Double)
    case simulatorPoolReady(size: Int)
    case mutantStarted(descriptor: MutantDescriptor, index: Int, total: Int)
    case mutantFinished(descriptor: MutantDescriptor, status: ExecutionStatus, index: Int, total: Int)
    case fallbackBuildStarted(filePath: String)
    case fallbackBuildFinished(filePath: String, success: Bool)
}
```

Lifecycle events emitted by `MutantExecutor` and its stages to the `ProgressReporter`.

---

## Reporting/RunnerSummary.swift

```swift
struct RunnerSummary: Sendable {
    let results: [ExecutionResult]
    let totalDuration: Double

    var killed: [ExecutionResult]
    var survived: [ExecutionResult]
    var unviable: [ExecutionResult]
    var timeouts: [ExecutionResult]
    var noCoverage: [ExecutionResult]
    var score: Double
    var resultsByFile: [String: [ExecutionResult]]
}
```

Aggregates all `ExecutionResult` values and computes the mutation score.

**Score formula:**

```
score = killed / (killed + survived + timeouts + noCoverage) × 100
```

`unviable` mutants are excluded from the denominator. When `denominator == 0` the score is `100.0`.

`resultsByFile` groups results by `descriptor.filePath`, used by all reporters to produce per-file breakdowns.

---

## Reporting/TextReporter.swift

```swift
struct TextReporter: Sendable {
    init(projectRoot: String = "")
    func report(_ summary: RunnerSummary)
    func format(_ summary: RunnerSummary) -> String
}
```

Prints a human-readable summary to stdout. Always active (not gated by a CLI flag).

Output sections:
1. Per-file table: relative path, score %, killed/survived/timeout/unviable counts
2. Survived mutants list: `<file>:<line>:<col>  <operator>` sorted by file then line
3. Overall score line
4. Total killed / survived / timeouts / unviable / noCoverage counts
5. Total duration

`format(_:)` is exposed separately for testing.

---

## Reporting/JsonReporter.swift

```swift
struct JsonReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a Stryker-compatible JSON report to `outputPath`. Encodes a `MutationReportPayload` with `JSONEncoder` (pretty-printed, sorted keys).

Fixed thresholds: `high = 80`, `low = 60`.

---

## Reporting/HtmlReporter.swift

```swift
struct HtmlReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a self-contained HTML dashboard to `outputPath`. Includes a per-file score table with `<details>` elements listing survived mutants inline. Score cells are colour-coded: green (100%), yellow (≥ 50%), red (< 50%).

---

## Reporting/SonarReporter.swift

```swift
struct SonarReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a SonarQube Generic Issue Import Format JSON file to `outputPath`. Reports survived mutants as `MAJOR` issues and `noCoverage` mutants as `MINOR` issues.

`engineId` is always `"swift-mutation-testing"`. `ruleId` is the operator identifier. `type` is `"CODE_SMELL"`.

---

## ExecutionStatus Extensions

### Reporting/ExecutionStatus+MutationReportStatus.swift

```swift
extension ExecutionStatus {
    var mutationReportStatus: String
}
```

Maps `ExecutionStatus` to the string value used in `MutationReportMutant.status`.

| Case | String |
|---|---|
| `.killed` | `"Killed"` |
| `.killedByCrash` | `"Crash"` |
| `.survived` | `"Survived"` |
| `.unviable` | `"Unviable"` |
| `.timeout` | `"Timeout"` |
| `.noCoverage` | `"NoCoverage"` |

---

### Reporting/ExecutionStatus+ProgressIcon.swift

```swift
extension ExecutionStatus {
    var progressIcon: String
}
```

Single-character icon displayed by `ConsoleProgressReporter` for each finished mutant.

| Case | Icon |
|---|---|
| `.killed`, `.killedByCrash` | `✓` |
| `.survived` | `✗` |
| `.unviable` | `⚠` |
| `.timeout` | `⏱` |
| `.noCoverage` | `–` |

---

## MutationReport Types

### Reporting/MutationReport/MutationReportPayload.swift

```swift
struct MutationReportPayload: Sendable, Encodable {
    let schemaVersion: String
    let thresholds: MutationReportThresholds
    let projectRoot: String
    let files: [String: MutationReportFile]
}
```

Root JSON object for the Stryker report format. `schemaVersion` is always `"1"`.

---

### Reporting/MutationReport/MutationReportFile.swift

```swift
struct MutationReportFile: Sendable, Encodable {
    let language: String
    let source: String
    let mutants: [MutationReportMutant]
}
```

`language` is always `"swift"`. `source` is the full source file content at report time.

---

### Reporting/MutationReport/MutationReportMutant.swift

```swift
struct MutationReportMutant: Sendable, Encodable {
    let id: String
    let mutatorName: String
    let originalText: String
    let replacement: String
    let location: MutationReportLocation
    let status: String
    let description: String
    let killedBy: String?
}
```

`killedBy` is populated only for `.killed(by:)` status.

---

### Reporting/MutationReport/MutationReportLocation.swift

```swift
struct MutationReportLocation: Sendable, Encodable {
    let start: MutationReportPosition
    let end: MutationReportPosition
}
```

`end.column` is computed as `start.column + originalText.count`.

---

### Reporting/MutationReport/MutationReportPosition.swift

```swift
struct MutationReportPosition: Sendable, Encodable {
    let line: Int
    let column: Int
}
```

---

### Reporting/MutationReport/MutationReportThresholds.swift

```swift
struct MutationReportThresholds: Sendable, Encodable {
    let high: Int
    let low: Int
}
```

Fixed values: `high = 80`, `low = 60`.

---

## Sonar Types

### Reporting/Sonar/SonarPayload.swift

```swift
struct SonarPayload: Sendable, Encodable {
    let issues: [SonarIssue]
}
```

Root JSON object for the SonarQube Generic Issue Import format.

---

### Reporting/Sonar/SonarIssue.swift

```swift
struct SonarIssue: Sendable, Encodable {
    let engineId: String
    let ruleId: String
    let severity: String
    let type: String
    let primaryLocation: SonarLocation
}
```

| Field | Value |
|---|---|
| `engineId` | `"swift-mutation-testing"` |
| `ruleId` | Operator identifier |
| `severity` | `"MAJOR"` (survived) or `"MINOR"` (noCoverage) |
| `type` | `"CODE_SMELL"` |

---

### Reporting/Sonar/SonarLocation.swift

```swift
struct SonarLocation: Sendable, Encodable {
    let message: String
    let filePath: String
    let textRange: SonarRange
}
```

`message` is `"[<operatorIdentifier>] <description>"`. `filePath` is relative to `projectRoot`.

---

### Reporting/Sonar/SonarRange.swift

```swift
struct SonarRange: Sendable, Encodable {
    let startLine: Int
    let endLine: Int
    let startColumn: Int
    let endColumn: Int
}
```

`endColumn` is `startColumn + originalText.count`. `startLine == endLine` (single-line range).

---

## Infrastructure/ProcessLaunching.swift

```swift
protocol ProcessLaunching: Sendable {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String)
}
```

Abstraction over process execution. `launch` discards output (stdout/stderr → `/dev/null`). `launchCapturing` accepts a `ProcessRequest` value, captures combined stdout+stderr, and returns it as a `String`.

Return value `-1` from either method means the process was killed by the timeout handler.

---

## Infrastructure/ProcessRequest.swift

```swift
struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    let timeout: Double
}
```

| Field | Description |
|---|---|
| `executableURL` | Path to the executable |
| `arguments` | Command-line arguments |
| `environment` | Full environment override (replaces inherited environment when non-nil) |
| `additionalEnvironment` | Key-value pairs merged into the existing environment |
| `workingDirectoryURL` | Working directory for the process |
| `timeout` | Maximum execution time in seconds |

---

## Infrastructure/ProcessRunner.swift

```swift
struct ProcessRunner: Sendable {
    var postTerminationCleanup: (@Sendable (Int32) -> Void)?
    let onTimeout: @Sendable (Int32) -> Void

    func launch(executableURL:arguments:workingDirectoryURL:timeout:) async throws -> Int32
    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String)
}
```

Low-level process execution engine. Uses `withTaskCancellationHandler` + `withCheckedThrowingContinuation` to bridge `Process.terminationHandler` into the Swift Concurrency runtime.

**Timeout handling:** a `Task` sleeping for `timeout` seconds marks a `KilledByUsFlag` and calls `onTimeout(pid)`. The `terminationHandler` checks the flag and returns `-1` instead of the actual exit code.

**Cancellation handling:** `onCancel` marks the flag and calls `onTimeout(pid)` immediately, ensuring the continuation is always resumed via the `terminationHandler`.

**Post-termination cleanup:** `postTerminationCleanup` is called after every process termination (success or failure), used by `SPMProcessLauncher` to clean up escaped child processes.

`launchCapturing` writes output to a temporary file (UUID-named) and reads it in the `terminationHandler` to avoid pipe buffer limits. Sets process group via `setpgid(pid, pid)` to enable group signaling.

---

## Infrastructure/SPMProcessLauncher.swift

```swift
struct SPMProcessLauncher: Sendable, ProcessLaunching {
    func launch(executableURL:arguments:workingDirectoryURL:timeout:) async throws -> Int32
    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String)
}
```

SPM-specific implementation of `ProcessLaunching`. Creates a `ProcessRunner` with:
- `onTimeout`: kills the process group via `kill(-pid, SIGKILL)` + `kill(pid, SIGKILL)`
- `postTerminationCleanup`: calls `killEscapedChildren(sandboxPath:)` to clean up orphaned child processes

**`killEscapedChildren(sandboxPath:)`** — inspects running processes via `sysctl` `KERN_PROCARGS2` to find any whose arguments contain the sandbox path prefix `xmr-`. Sends `SIGKILL` to matching processes to prevent resource leaks from spawned child processes that outlive the parent.

---

## Infrastructure/XCTestRunPlist.swift

```swift
struct XCTestRunPlist: Sendable, Equatable {
    init?(_ data: Data)
    func activating(_ mutantID: String) -> Data
}
```

Wraps the raw plist `Data` from the `.xctestrun` file.

`activating(_:)` injects `mutantID` into `EnvironmentVariables.__SWIFT_MUTATION_TESTING_ACTIVE` for every test target in the plist. Handles both the `TestConfigurations` format (Xcode 15+) and the legacy flat dictionary format. Returns a fresh XML plist `Data` — the original is not mutated.

---

## Infrastructure/TestFilesHasher.swift

```swift
struct TestFilesHasher: Sendable {
    func hashPerFile(projectPath: String) -> [String: String]
    func testFilePaths(projectPath: String) -> [String]
}
```

Provides per-file test hashing and test file path enumeration for granular cache invalidation.

| Method | Description |
|---|---|
| `hashPerFile(projectPath:)` | Returns a dictionary mapping relative test file paths to their SHA256 content hashes. Symlinks pointing outside the project root use absolute paths as keys to avoid collisions |
| `testFilePaths(projectPath:)` | Returns all test file paths in the project |

**Test file collection:** files whose containing directory name ends with `Tests` or `Specs`, or whose filename matches `*Tests.swift` or `*Specs.swift`.

---

← [Result Parsing & Cache](08-result-parsing-cache.md) | [Index →](README.md)
