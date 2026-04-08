# Result Parsing & Cache

← [Execution](07-execution.md) | Next: [Reporting & Infrastructure →](09-reporting-infrastructure.md)

---

## Execution/TestResultResolver.swift

```swift
struct TestResultResolver: Sendable {
    let launcher: any ProcessLaunching

    func resolve(
        launch: TestLaunchResult,
        projectType: ProjectType,
        timeout: TimeInterval
    ) async throws -> TestRunOutcome
}
```

Delegates to the appropriate parser based on project type:
- `.xcode` → `ResultParser` (xcresulttool + output parsing)
- `.spm` → `SPMResultParser` (output-only parsing)

---

## Execution/Parsing/ResultParser.swift

```swift
struct ResultParser: Sendable {
    init(launcher: any ProcessLaunching)
    func parse(
        exitCode: Int32,
        output: String,
        xcresultPath: String,
        timeout: Double
    ) async throws -> TestRunOutcome
}
```

Determines the `TestRunOutcome` of a completed test invocation.

```mermaid
flowchart TD
    EC{exit code?} -- -1 --> TO[.timedOut]
    EC -- 0 --> SUCCESS[.testsSucceeded]
    EC -- non-zero --> XCR[XCResultParser.parse xcresultPath]
    XCR -- failures found --> KILLED[.testsKilled reason from xcresult]
    XCR -- no failures --> STDOUT[TestOutputParser.parse output]
    STDOUT -- failure pattern --> KILLED2[.testsKilled reason from stdout]
    STDOUT -- crash pattern --> CRASH[.processCrashed]
    STDOUT -- no pattern --> KILLED3[.testsKilled other]
```

Exit code `-1` is the sentinel set by `ProcessLauncher` when it kills the process due to timeout. Exit code `0` with no test failures is `.testsSucceeded` (survived). For non-zero exit codes, `XCResultParser` is tried first against the `.xcresult` bundle; `TestOutputParser` is the stdout/stderr fallback.

---

## Execution/Parsing/TestRunOutcome.swift

```swift
enum TestRunOutcome: Sendable {
    case testsSucceeded
    case testsFailed(failingTest: String)
    case crashed
    case timedOut
    case unviable

    var asExecutionStatus: ExecutionStatus { get }
}
```

Intermediate result from `TestResultResolver`/`ResultParser`/`SPMResultParser`, converted to `ExecutionStatus` via `asExecutionStatus`.

| Case | Maps to |
|---|---|
| `testsSucceeded` | `.survived` |
| `testsFailed(failingTest:)` | `.killed(by: failingTest)` |
| `crashed` | `.killedByCrash` |
| `timedOut` | `.timeout` |
| `unviable` | `.unviable` |

---

## Execution/Parsing/TestOutputParser.swift

```swift
struct TestOutputParser: Sendable {
    func parse(_ output: String) -> TestRunOutcome
}
```

Scans stdout/stderr for known failure and crash patterns when `xcresulttool` yields no results.

**Failure patterns detected:**

| Framework | Pattern |
|---|---|
| XCTest | `Test Case '-[…]' failed` |
| Swift Testing | `Test "…" failed` |

**Crash patterns detected:**

`Fatal error`, `EXC_BAD_INSTRUCTION`

Returns `.testsKilled(reason: <first matching line>)` for test failures, `.processCrashed` for crashes, or `.testsKilled(reason: "other")` when no pattern matches but the exit code was non-zero.

---

## Execution/Parsing/SPMResultParser.swift

```swift
struct SPMResultParser: Sendable {
    func parse(exitCode: Int32, output: String) -> TestRunOutcome
}
```

Parses SPM test results from exit code and stdout/stderr output only (no `.xcresult` bundles). Uses `TestOutputParser` to detect failure patterns.

| Condition | Outcome |
|---|---|
| Exit code `-1` | `.timedOut` |
| Exit code `0` | `.testsSucceeded` |
| Non-zero + test failure pattern | `.testsFailed(failingTest:)` |
| Non-zero + empty output | `.crashed` |
| Non-zero + no parseable failure | `.unviable` |

---

## Execution/Parsing/XCResultParser.swift

```swift
struct XCResultParser: Sendable {
    init(launcher: any ProcessLaunching)
    func parse(xcresultPath: String) async throws -> TestRunOutcome?
}
```

Invokes `xcresulttool get test-results tests` on the `.xcresult` bundle and parses the JSON output. Walks the `testNodes` tree recursively looking for nodes where `nodeType == "Test Case"` and `result == "Failed"`. Returns the first failure message as `.testsKilled(reason:)`, or `nil` if no failures are found or the invocation fails.

---

## Cache/CacheStore.swift

```swift
actor CacheStore {
    static let directoryName: String
    init(storePath: String)
    func result(for key: MutantCacheKey) -> ExecutionStatus?
    func killerTestFile(for key: MutantCacheKey) -> String?
    func store(status: ExecutionStatus, for key: MutantCacheKey, killerTestFile: String? = nil)
    func load() throws
    func persist() throws
    func loadMetadata() throws -> CacheMetadata?
    func persistMetadata(_ metadata: CacheMetadata) throws
    func invalidate(diff: TestFileDiff)
    func changedTestFiles(current: [String: String]) throws -> TestFileDiff
}
```

Persists execution results across runs with granular per-file invalidation. All reads and writes are serialised by the actor.

| Constant | Value |
|---|---|
| `directoryName` | `".swift-mutation-testing-cache"` |

Cache is stored at `<project>/.swift-mutation-testing-cache/results.json` as a JSON array of `CacheEntry` values (key + status + killerTestFile).

`load()` is a no-op if the cache file does not exist. `persist()` creates the directory if needed and writes atomically.

**Granular invalidation methods:**

| Method | Description |
|---|---|
| `killerTestFile(for:)` | Returns the stored killer test file path for a cached entry |
| `store(status:for:killerTestFile:)` | Stores an execution result with optional killer test file metadata |
| `changedTestFiles(current:)` | Compares current per-file test hashes against stored metadata to produce a `TestFileDiff` |
| `invalidate(diff:)` | Removes cached entries based on status-aware rules (see Architecture docs) |
| `persistMetadata(_:)` | Writes `CacheMetadata` (test file hashes) to disk alongside the results cache |

---

## Cache/MutantCacheKey.swift

```swift
struct MutantCacheKey: Hashable, Sendable, Codable {
    let fileContentHash: String
    let operatorIdentifier: String
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String

    static func hash(of content: String) -> String
    static func make(for mutant: MutantDescriptor) -> MutantCacheKey
}
```

SHA256-derived cache key. Stable across test-only changes — invalidation is handled granularly by `CacheStore.invalidate(diff:)`.

| Field | Source |
|---|---|
| `fileContentHash` | SHA256 of `mutatedSourceContent` for incompatible mutants; SHA256 of the source file at `filePath` for schematizable mutants |
| `operatorIdentifier` | Operator name |
| `utf8Offset` | Mutation position |
| `originalText` | Token before mutation |
| `mutatedText` | Token after mutation |

`make(for:)` computes `fileContentHash` from `descriptor.mutatedSourceContent` (for incompatible mutants) or from the on-disk content at `descriptor.filePath` (for schematizable mutants).

---

## Cache/TestFileDiff.swift

```swift
struct TestFileDiff: Sendable {
    let added: Set<String>
    let modified: Set<String>
    let removed: Set<String>
    var hasChanges: Bool
}
```

Represents changes to test files between cache runs. Produced by `CacheStore.changedTestFiles(current:)` and consumed by `CacheStore.invalidate(diff:)`.

| Field | Description |
|---|---|
| `added` | Test file paths present in current hashes but absent from stored metadata |
| `modified` | Test file paths present in both but with different content hashes |
| `removed` | Test file paths present in stored metadata but absent from current hashes |
| `hasChanges` | `true` when any of the three sets is non-empty |

---

## Cache/KillerTestFileResolver.swift

```swift
struct KillerTestFileResolver: Sendable {
    let testFilePaths: [String]
    func resolve(testName: String) -> String?
}
```

Maps killer test names back to their source file paths. Supports both XCTest class names (e.g. `CalculatorTests`) and Swift Testing function names (e.g. `addReturnsSum()`).

Resolution strategy: extracts the class or function name from the test name, then searches `testFilePaths` for a file whose name contains the extracted identifier.

---

← [Execution](07-execution.md) | Next: [Reporting & Infrastructure →](09-reporting-infrastructure.md)
