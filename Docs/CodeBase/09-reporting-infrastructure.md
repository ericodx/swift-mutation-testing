# Reporting & Infrastructure

← [Result Parsing & Cache](08-result-parsing-cache.md) | Next: [Quality Gate →](10-quality-gate.md)

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

Serialises progress output to stdout. Each `RunnerEvent` case maps to one or two `StandardOutput.write` calls, each line but the headings indented by two spaces. `.mutantStarted`, `.fallbackBuildStarted`, and `.fallbackBuildFinished` are no-ops (no output).

**Output per event:**

| Event | Output |
|---|---|
| `.discoveryFinished` | `✓ Discovery: N mutants (M schematizable[, K incompatible]) in X.Xs` |
| `.loadedFromCache` | `✓ Loaded N mutants from cache` |
| `.buildStarted` | blank line + `Building for testing...` |
| `.buildFinished` | `✓ Built in X.Xs` |
| `.schemaNarrowed` | `⚠ Schema did not build: retrying without N mutants, to be built one by one` (`1 mutant, to be built on its own` for one) |
| `.workersReady` | `✓ N simulators ready` or `✓ N workers ready` (singular for one) + blank line + `Testing mutants...` |
| `.mutantFinished` | `<icon> <index>/<total>  <operator>  <filename>:<line>` |

Progress icon is provided by `ExecutionStatus.progressIcon`.

---

## Reporting/SilentProgressReporter.swift

```swift
struct SilentProgressReporter: Sendable, ProgressReporter {
    func report(_ _: RunnerEvent) async
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
    case schemaNarrowed(excludedCount: Int)
    case workersReady(count: Int, usesSimulators: Bool)
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

    let killed: [ExecutionResult]
    let survived: [ExecutionResult]
    let unviable: [ExecutionResult]
    let timeouts: [ExecutionResult]
    let noCoverage: [ExecutionResult]
    let score: Double
    let resultsByFile: [String: [ExecutionResult]]
    let fromCache: [ExecutionResult]
    let integrityWarnings: [ExecutionResult]
    let activationNotMeasured: [ExecutionResult]

    init(results: [ExecutionResult], totalDuration: Double)

    var detected: [ExecutionResult]
    var undetected: [ExecutionResult]
    var files: [(path: String, summary: RunnerSummary)]

    static func byLocation(_ results: [ExecutionResult]) -> [ExecutionResult]
}
```

Aggregates all `ExecutionResult` values and computes the mutation score. `init` sorts the results into the five status buckets in one pass, and in the same pass works out the score, groups the results by file and collects the cached results, the integrity warnings and the results with no activation measured — so every report reads stored values, where each property used to filter `results` again on every access (`score` alone ran four filters). `files` is still built on demand from the stored `resultsByFile`, since storing it would make each per-file summary build its own. `killed` includes `.killedByCrash`.

**Score formula:**

```
detected   = killed + timeouts
undetected = survived + noCoverage
score      = detected / (detected + undetected) × 100
```

`unviable` mutants are on neither side. When no mutant is detected or undetected the score is `100.0`. This is the formula the Stryker report schema applies to the statuses `JsonReporter` emits, so the JSON report scores the same in any Stryker-compatible viewer — see [Stryker Compatibility](../STRYKER-COMPATIBILITY.md). It is the only score formula: the per-file scores are `RunnerSummary` values too, from `files`.

`resultsByFile` groups results by `descriptor.filePath`. `files` turns that into one `RunnerSummary` per file, in path order — the per-file tables of `TextReporter`, `HtmlReporter` and `MarkdownReporter` iterate it. `byLocation(_:)` sorts results by file, line and column; every report that lists mutants — the survived and integrity lists, the Markdown tables, the SARIF results — sorts through it.

### Integrity lists

`integrityWarnings` are the kills and timeouts whose mutated code never ran (`activated == false`); `activationNotMeasured` are the results other than `unviable` with no measurement at all (`activated == nil`), such as the incompatible mutants that could not be instrumented. `TextReporter` and `MarkdownReporter` print both.

### Reporting/ExecutionResult+ReportStatusReason.swift

```swift
extension ExecutionResult {
    var reportStatusReason: String?
}
```

The `statusReason` the JSON report and the integrity list carry: `crash`, `crash without activation`, `killed without activation`, `timed out without activation`, or `nil`.

### Reporting/RunnerSummary+DetectionLine.swift

```swift
extension RunnerSummary {
    var detectionLine: String
}
```

`Detected: <n> (killed <k>, timeout <t>) / Undetected: <n> (survived <s>, no coverage <c>)` — the two sides of the score, printed under it by `TextReporter`, `HtmlReporter` and `MarkdownReporter` so that a score earned by timeouts is visible as such.

### Reporting/RunnerSummary+Cache.swift

```swift
extension RunnerSummary {
    var cacheLine: String?
}
```

`Verdicts from cache: <n> of <total>`, counted from `fromCache`; `nil` when no verdict came from the cache. `TextReporter` and `MarkdownReporter` print it.

---

## Reporting/TextReporter.swift

```swift
struct TextReporter: Sendable {
    static let integrityWarningsListed: Int
    init(projectRoot: String = "")
    func report(_ summary: RunnerSummary)
    func format(_ summary: RunnerSummary) -> String
}
```

Prints a human-readable summary through `StandardOutput`. Always active (not gated by a CLI flag): `RunConclusion.conclude` prints it before the gate and the report files. Paths are relative to `projectRoot`, both sides resolved through symlinks; an empty root leaves them absolute.

Output sections:
1. `Results by file:` — one line per file (`RunnerSummary.files`): relative path, score %, and the killed, survived, timeout, unviable and no coverage counts
2. Undetected mutants list — survived and no coverage: `<file>:<line>:<col>   <operator>   <survived | no coverage>` sorted by location (`RunnerSummary.byLocation`), when there are any
3. Integrity warnings — kills and timeouts whose code never ran, the first `integrityWarningsListed` (10) with their reason, then a count — when there are any
4. Overall score line
5. Detection line (`RunnerSummary.detectionLine`)
6. Total killed / survived / timeouts / unviable / noCoverage counts
7. `Activation not measured: N mutants`, when N > 0
8. `Verdicts from cache: N of M` (`RunnerSummary.cacheLine`), when any result has `fromCache`
9. Total duration

`format(_:)` is exposed separately for testing.

---

## Reporting/JsonReporter.swift

```swift
struct JsonReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary, identity: RunIdentity? = nil) throws
}
```

Writes a Stryker-compatible JSON report to `outputPath`. With an identity, the schema's free-form `config` object (`MutationReportConfig`) carries `toolVersion`, `planSha256` and, for a shard, `shard`; every mutant carries `activated` and `duration` next to `fingerprint`. `ResultMerger` reads these back, so the `MutationReport*` types are `Codable`, not only `Encodable`. Encodes a `MutationReportPayload` with `JSONEncoder` (pretty-printed, sorted keys). Each file's key is its path relative to `projectRoot` with a leading `/`, computed by a `ProjectRelativePath.Resolver` so that a root reached through a symlink still yields `/Sources/…`; a file outside the root keeps its absolute path. Each file's `source` is read from disk at report time, `""` when it cannot be.

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

Writes a self-contained HTML dashboard to `outputPath`. Shows the overall score, the detection line and the totals, then a per-file score table — killed, survived, timeouts, unviable, no coverage — with `<details>` elements listing each file's survived mutants inline, by line. Score cells are colour-coded: green (100%), yellow (≥ 50%), red (< 50%). Every interpolated value — the file path, the operator, the mutation description and the detection line — goes through `String.htmlEscaped` (`&`, `<`, `>`, `"`, `'`), so a `<` or `&&` mutation keeps the table intact and a string literal cannot inject markup. File paths are relative to `projectRoot`, computed by `ProjectRelativePath`, with no leading `/`.

---

## Reporting/String+HtmlEscaped.swift

```swift
extension String {
    var htmlEscaped: String
}
```

Replaces `&`, `<`, `>`, `"` and `'` with their character references, so that any text can be placed in an HTML element or attribute value. `HtmlReporter` applies it to every value it interpolates.

---

## Reporting/SonarReporter.swift

```swift
struct SonarReporter: Sendable {
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary) throws
}
```

Writes a SonarQube Generic Issue Import Format JSON file (pretty-printed) to `outputPath`. Reports survived mutants as `MAJOR` issues and `noCoverage` mutants as `MINOR` issues, the survived ones first. Each issue's `filePath` is relative to `projectRoot`, computed by `ProjectRelativePath`, with no leading `/`, as the generic issue import expects.

`engineId` is always `"swift-mutation-testing"`. `ruleId` is the operator identifier. `type` is `"CODE_SMELL"`.

---

## Reporting/SarifReporter.swift

```swift
struct SarifReporter: Sendable {
    static let resultLimit: Int
    static let fingerprintKey: String
    static let sourceRootBaseId: String
    let outputPath: String
    let projectRoot: String
    var resultLimit: Int
    func report(_ summary: RunnerSummary) throws
    func buildLog(_ summary: RunnerSummary) -> SarifLog
    static func position(of identifier: String, in sorted: [String]) -> Int
}
```

| Constant | Value |
|---|---|
| `resultLimit` | `25_000`; the instance property defaults to it |
| `fingerprintKey` | `"swiftMutationTesting/v1"` |
| `sourceRootBaseId` | `"%SRCROOT%"` |

Writes a SARIF 2.1.0 log, the format GitHub code scanning reads, with one `run` whose results are the undetected mutants — survived and no coverage, the same set `SonarReporter` reports — sorted by file, line and column.

| Part | Content |
|---|---|
| `tool.driver` | `Version.name`, `Version.number`, the repository URL, and one rule per operator present among the reported results, sorted by identifier (`SarifRuleCatalog`) |
| `originalUriBaseIds` | `%SRCROOT%` → the canonical project root as a `file://` URI, so code scanning maps the paths even when the project is a subdirectory of the repository |
| `columnKind` | `utf16CodeUnits` |
| result `ruleId`, `ruleIndex` | the operator identifier, and its position in the driver's sorted rules |
| result `level` | `warning` for both statuses |
| result `message` | `Mutant survived: <description>.` and either `No test failed when this code was changed.` or `No test executed this code.` |
| result location | the project-relative path under `%SRCROOT%`; `startLine`, and `startColumn`/`endColumn` in UTF-16 code units |
| `partialFingerprints` | `swiftMutationTesting/v1` → the mutant's `MutantFingerprint`, so an alert survives unrelated edits and closes once the mutant is killed |
| `properties` | `mutationStatus` (`survived` or `noCoverage`) and `replacement` |

SwiftSyntax reports columns in UTF-8 bytes. The reporter reads each mutant's line from its file, once per file, and converts the column so an annotation after a non-ASCII character is not shifted; when the file cannot be read it keeps the recorded column. Beyond `resultLimit` results — code scanning's limit per upload — it keeps the first ones and prints a warning through `StandardError`. `report` encodes the log pretty-printed, with sorted keys and no escaped slashes.

`position(of:in:)` is a binary search for the lower bound of `identifier` in the sorted operator list, which is each result's `ruleIndex`. The identifier is always in the list — the list is built from the same results — so there is no fallback to cover; the rule index used to be looked up in a dictionary built alongside the rules, with a fallback no input reached.

### Reporting/Sarif/

```swift
struct SarifLog: Sendable, Encodable {
    let schema: String
    let version: String
    let runs: [SarifRun]
    init(runs: [SarifRun])
}

struct SarifRun: Sendable, Encodable {
    let tool: SarifTool
    let originalUriBaseIds: [String: SarifArtifactLocation]
    let columnKind: String
    let results: [SarifResult]
    init(tool: SarifTool, originalUriBaseIds: [String: SarifArtifactLocation], results: [SarifResult])
}

struct SarifTool: Sendable, Encodable { let driver: SarifDriver }

struct SarifDriver: Sendable, Encodable {
    let name: String
    let version: String
    let informationUri: String
    let rules: [SarifRule]
}

struct SarifRule: Sendable, Encodable {
    let id: String
    let name: String
    let shortDescription: SarifMessage
    let fullDescription: SarifMessage
    let helpUri: String
    let defaultConfiguration: SarifConfiguration
}

struct SarifConfiguration: Sendable, Encodable { let level: String }
struct SarifMessage: Sendable, Encodable { let text: String }

struct SarifResult: Sendable, Encodable {
    let ruleId: String
    let ruleIndex: Int
    let level: String
    let message: SarifMessage
    let locations: [SarifLocation]
    let partialFingerprints: [String: String]
    let properties: SarifResultProperties
}

struct SarifResultProperties: Sendable, Encodable {
    let mutationStatus: String
    let replacement: String
}

struct SarifLocation: Sendable, Encodable { let physicalLocation: SarifPhysicalLocation }

struct SarifPhysicalLocation: Sendable, Encodable {
    let artifactLocation: SarifArtifactLocation
    let region: SarifRegion
}

struct SarifArtifactLocation: Sendable, Encodable {
    let uri: String
    var uriBaseId: String?
}

struct SarifRegion: Sendable, Encodable {
    let startLine: Int
    let startColumn: Int
    let endColumn: Int
}

enum SarifRuleCatalog {
    static let helpUri: String
    static func rule(for operatorIdentifier: String) -> SarifRule
}
```

One file per type, each an `Encodable` mirror of the SARIF 2.1.0 object of the same name. `SarifLog.init(runs:)` fixes `schema` — encoded as `$schema` — to `https://json.schemastore.org/sarif-2.1.0.json` and `version` to `2.1.0`; `SarifRun.init` fixes `columnKind` to `utf16CodeUnits`. `uriBaseId` is `nil` in `originalUriBaseIds` and `%SRCROOT%` in a result's location.

`SarifRuleCatalog.rule(for:)` looks the operator up in `OperatorRegistry` and uses its identifier as the rule's `id` and `name`, its `summary` as the short description and its `explanation` as the full one, with `helpUri` — the operator reference in `Docs/USAGE.MD` — and a default level of `warning`. An unknown operator gets its identifier as the short description and `Mutates the code.` as the full one.

---

## Reporting/MarkdownReporter.swift

```swift
struct MarkdownReporter: Sendable {
    static let listedLimit: Int
    let outputPath: String
    let projectRoot: String
    func report(_ summary: RunnerSummary, gate: GateResult? = nil) throws
    func format(_ summary: RunnerSummary, gate: GateResult? = nil) -> String
}
```

Writes a Markdown summary for CI job summaries and merge request notes, under a `## Mutation testing` heading:

1. The score, the detection line (`RunnerSummary.detectionLine`) and the totals; then, when there are any, the integrity warnings as a count, `Activation not measured: N mutants`, and the cache line (`RunnerSummary.cacheLine`)
2. The quality gate, when a result is given: passed or failed, its checks, the informational lines (`GateResult.notes`), and a table of its new undetected mutants
3. `Results by file`, one table row per file as in `TextReporter` — omitted for an empty run
4. The undetected mutants, sorted by location — the first `listedLimit` (20), with a count of the rest

Each mutant table lists at most `listedLimit` rows. Paths are relative to `projectRoot` through `ProjectRelativePath`.

Table cells escape `|`, and the mutation is written as code with backticks replaced, so a `||` mutation cannot break the table.

---

## Reporting/GateResult+Summary.swift

```swift
extension GateResult {
    var checksNewUndetected: Bool
    var newUndetectedSummary: String
    var notes: [String]
    static func count(_ value: Int, _ noun: String) -> String
}

extension GateResult.Check {
    var summary: String
}
```

| Check | `summary` |
|---|---|
| `.minScore` | `score 90.4% ≥ 85.0%`, or `<` when it fails |
| `.scoreDrop` | `score drop 0.7 pts ≤ 2.0 pts`, or `>` when it fails; `score did not drop (max drop 2.0 pts)` when the drop is not positive |
| `.newUndetected` | `1 new undetected mutant (max 0)` |
| `.integrityWarnings` | `2 integrity warnings (max 0)` |

`count(_:_:)` writes a count and its noun, with an `s` unless the count is one. `checksNewUndetected` says whether the policy has a `.newUndetected` check, and `newUndetectedSummary` counts `newUndetected`.

The wording of the gate, shared by `GateReporter` and `MarkdownReporter` so the console and the job summary say the same thing. `notes` are the informational lines beyond the checks: the new undetected mutants when no check counts them, and the mutants detected now that the baseline left undetected; each reporter only adds its own bullet.

---

## Reporting/ReportFormat.swift

```swift
enum ReportFormat: String, CaseIterable, Sendable {
    case json, html, sonar, sarif, markdown

    var flag: String
    var fileKey: String
    var label: String
    var exampleFile: String
    var helpLine: String
    static func named(flag: String) -> ReportFormat?
}
```

| Case | `flag` | `label` | `exampleFile` |
|---|---|---|---|
| `json` | `--output` | `JSON` | `mutation-report.json` |
| `html` | `--html-output` | `HTML` | `mutation-report.html` |
| `sonar` | `--sonar-output` | `Sonar` | `sonar-mutation-report.json` |
| `sarif` | `--sarif-output` | `SARIF` | `mutation-report.sarif` |
| `markdown` | `--markdown-output` | `Markdown` | `mutation-summary.md` |

`fileKey` is the flag without its dashes — the `.swift-mutation-testing.yml` key. `exampleFile` is the path `init` suggests. `helpLine` is the flag's line in `HelpText.usage`: the flag and its argument padded to 30 columns, then the description.

The one description of each report file. `CommandLineParser` reads a format's path off `named(flag:)`, `ConfigurationResolver` takes the CLI path or else the file's `fileKey`, `RunnerConfiguration.ReportingOptions.outputs` keeps them by format, `HelpText` and `ConfigurationFileWriter` write their lines from `helpLine` and `exampleFile`, and `ReportWriter` writes them in case order. Adding a format is a case here and its reporter in `ReportWriter`'s exhaustive `switch`, which the compiler asks for.

---

## Reporting/ReportWriter.swift

```swift
struct ReportWriter: Sendable {
    let configuration: RunnerConfiguration

    func write(_ summary: RunnerSummary, gate: GateResult? = nil, identity: RunIdentity? = nil)
}
```

Writes every report file the configuration asks for, in `ReportFormat` order, each from its path in `configuration.reporting.outputs` through an exhaustive `switch` over the format. Formats without a path are skipped; when any is requested it prints a blank line, then `  ✓ <label> report: <path>` per file written, and a failure becomes `Warning: could not write <label> report to '<path>': …` on `StandardError` rather than ending the run.

---

## ExecutionStatus Extensions

### Reporting/ExecutionStatus+MutationReportStatus.swift

```swift
extension ExecutionStatus {
    var mutationReportStatus: String
    var mutationReportStatusReason: String?
}
```

Maps `ExecutionStatus` to the Stryker schema values used in `MutationReportMutant.status` and `MutationReportMutant.statusReason`.

| Case | `status` | `statusReason` |
|---|---|---|
| `.killed` | `"Killed"` | `nil` |
| `.killedByCrash` | `"Killed"` | `"crash"` — the JSON report uses `ExecutionResult.reportStatusReason`, which also names a missing activation |
| `.survived` | `"Survived"` | `nil` |
| `.unviable` | `"CompileError"` | `nil` |
| `.timeout` | `"Timeout"` | `nil` |
| `.noCoverage` | `"NoCoverage"` | `nil` |

Every value is one the schema defines, and each lands on the side of the schema's score that `RunnerSummary` puts it on.

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
struct MutationReportPayload: Sendable, Codable {
    let schemaVersion: String
    let thresholds: MutationReportThresholds
    let projectRoot: String
    let files: [String: MutationReportFile]
    let config: MutationReportConfig?
}

struct MutationReportConfig: Sendable, Codable, Equatable {
    let toolVersion: String
    let planSha256: String
    let shard: String?
}
```

Root JSON object for the Stryker report format. `schemaVersion` is always `"1"`. `config` is the run's `RunIdentity` — the schema leaves the object free-form — with `toolVersion` from `Version.number` and `shard` as `i/n`; `nil`, and omitted, when the report is written without an identity. `ResultMerger` refuses a report without it.

---

### Reporting/MutationReport/MutationReportFile.swift

```swift
struct MutationReportFile: Sendable, Codable {
    let language: String
    let source: String
    let mutants: [MutationReportMutant]
}
```

`language` is always `"swift"`. `source` is the full source file content at report time.

---

### Reporting/MutationReport/MutationReportMutant.swift

```swift
struct MutationReportMutant: Sendable, Codable {
    let id: String
    let mutatorName: String
    let originalText: String
    let replacement: String
    let location: MutationReportLocation
    let status: String
    let statusReason: String?
    let description: String
    let killedBy: [String]?
    let duration: Int?
    let fingerprint: String
    let activated: Bool?
}
```

`killedBy` is populated only for `.killed(by:)` status, as a one-element array: the schema types it `string[]`, and a mutant's run stops at its first failing test. `statusReason` comes from `ExecutionResult.reportStatusReason`. `duration` is the test duration in whole milliseconds, `nil` when it is zero, as it is for a verdict from the cache. Optional fields are omitted from the JSON when `nil`. `fingerprint` is the mutant's `MutantFingerprint` and `activated` whether the mutated code ran — extra properties the Stryker schema allows.

---

### Reporting/MutationReport/MutationReportLocation.swift

```swift
struct MutationReportLocation: Sendable, Codable {
    let start: MutationReportPosition
    let end: MutationReportPosition
}
```

`end.column` is computed as `start.column + originalText.utf8.count`: `start.column` is the UTF-8 column SwiftSyntax reports, so the length is counted in the same unit — counting characters ended the range early on any text with a multi-byte character.

---

### Reporting/MutationReport/MutationReportPosition.swift

```swift
struct MutationReportPosition: Sendable, Codable {
    let line: Int
    let column: Int
}
```

---

### Reporting/MutationReport/MutationReportThresholds.swift

```swift
struct MutationReportThresholds: Sendable, Codable {
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

`endColumn` is `startColumn + originalText.utf8.count`, in UTF-8 columns like `startColumn`. `startLine == endLine` (single-line range).

---

## Reporting/MutantLogWriter.swift

```swift
struct MutantLogWriter: Sendable {
    init?(directory: String?)

    func write(
        mutant: MutantDescriptor, status: ExecutionStatus, duration: Double, output: String, activated: Bool? = nil
    )
    func write(baselineOutput output: String)
}
```

Writes one `<mutant id>.log` per mutant into the directory given by `--keep-logs`, creating it if needed, holding a header — id, file, line and column, operator, the mutation, verdict, whether the mutated code ran, duration — then `---` and the whole test output that produced it. `write(baselineOutput:)` writes the baseline's test output to `baseline.log` in the same directory. Write failures are ignored: a log is a convenience, not a result. The initialiser fails when no directory was configured, so the call site is `MutantLogWriter(directory:)?.write(…)` and the feature costs nothing when it is off.

The verdict in the header uses the tool's own labels (`Killed by <test>`, `Crash`, `Survived`, `Unviable`, `Timeout`, `NoCoverage`), not the Stryker values of `mutationReportStatus`: the log is read by someone chasing one mutant, and `Crash` says more there than `Killed`.

Every verdict is logged, including `unviable`: a mutant that did not compile is exactly the one whose build output someone will want to read.

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

Return value `-1` from either method means the runner ended the process itself, at its timeout or on cancellation; a request stopped by its `stopRule` returns the rule's exit code instead.

---

## Infrastructure/RunnerLaunching.swift

```swift
protocol RunnerLaunching: ProcessLaunching {
    func makeRunner() -> ProcessRunner
}
```

A launcher that runs every process through a fresh `ProcessRunner`. Its extension gives `launch` and `launchCapturing`, each delegating to `makeRunner()`, so `SPMProcessLauncher` and `XcodeProcessLauncher` supply only the runner — their timeout handling and post-termination cleanup — instead of repeating the same two methods.

---

## Infrastructure/ProcessRequest.swift

```swift
struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    var timeout: Double
    var stopRule: OutputStopRule?

    func withTimeout(_ timeout: Double) -> ProcessRequest
    func stopping(at rule: OutputStopRule) -> ProcessRequest
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
| `stopRule` | When set, the runner ends the process as soon as a line of its output is what the rule stops at, and reports the rule's exit code instead of the process's own |

`withTimeout(_:)` and `stopping(at:)` return a copy with that one field changed.

**`OutputStopRule`** (`Infrastructure/OutputStopRule.swift`) names the kind of line to stop at and the exit code to report when one is seen. `.firstTestFailure` stops at a line `TestOutputParser.failingTest(in:)` reads as a failed test — the XCTest `Test Case '-[…]' failed` line, at the start of the line, and Swift Testing's `✘ Test "…" recorded an issue` and `failed after` — with exit code 1, which is what both libraries exit with on a failure anyway. A line that merely quotes such text, such as the `started` line of a parameterized test whose argument is a failure line, does not stop the run: the rule asks the same parser that would name the kill, so a stop happens exactly where a kill would be read.

---

## Infrastructure/ProcessRunner.swift

```swift
struct ProcessRunner: Sendable {
    var postTerminationCleanup: (@Sendable (Int32) -> Void)?
    let onTimeout: @Sendable (Int32) -> Void
    var readCapturedOutput: @Sendable (URL) throws -> String
    var processGroups: ProcessGroupRegistry = .shared
    var isCancelled: @Sendable () -> Bool = { Task.isCancelled }

    final class KilledByUsFlag: @unchecked Sendable {
        var value: Bool { get }
        func mark()
    }

    func launch(executableURL:arguments:workingDirectoryURL:timeout:) async throws -> Int32
    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String)
    static func checkOwnGroup(_ pid: pid_t, groupOf: (pid_t) -> pid_t = getpgid, warning: OnceWarning = groupWarning)
    static func track(_ pid: pid_t, isRunning: () -> Bool, in processGroups: ProcessGroupRegistry)
}
```

Low-level process execution engine. Uses `withTaskCancellationHandler` + `withCheckedThrowingContinuation` to bridge `Process.terminationHandler` into the Swift Concurrency runtime.

**Reading the capture back:** `readCapturedOutput` defaults to reading the file as bytes and decoding them with `String(decoding:as: UTF8.self)`, which replaces an invalid byte rather than failing — the way `OutputWatcher` reads the same file. A run stopped at its first failure or at a timeout is killed mid-write, and Swift Testing prints multi-byte symbols (`✘`, `✔`); a strict decode would turn the whole log into `""` over one cut character, and the mutant into a crash with no killer test. Only a file that cannot be read at all yields empty output.

Both launch paths share their plumbing: the private `awaitTermination(of:killedByUs:start:)` wraps the continuation and its cancellation handler, and the private `run(_:timeoutTask:continuation:onLaunchFailure:result:)` installs the `terminationHandler`, starts the process, checks its group and tracks it — or, when `process.run()` throws, cancels the timeout task, runs `onLaunchFailure` (for `launchCapturing`, closing and removing the capture file) and resumes with the error. Each path only supplies its timeout task and the `result` closure that turns the terminated process into its return value.

**Timeout handling:** a `Task` sleeping for `timeout` seconds marks a `KilledByUsFlag` — a lock-guarded flag set from one task and read from the `terminationHandler` — and calls `onTimeout(pid)`. The `terminationHandler` checks the flag and returns `-1` instead of the actual exit code.

**Stopping at a marker:** when the request carries a `stopRule`, that same `Task` polls the capture file every 100ms instead of sleeping through the whole timeout. `OutputWatcher` reads only the bytes written since its last look and keeps the unterminated tail, so a marker split across two writes is still seen. On a match the process is ended through the same `onTimeout(pid)` path a timeout uses — group `SIGTERM`, then the launcher's escalation — but a second flag records *why* — the private `StopFlags` carries the two into the capturing path — and the `terminationHandler` reports the rule's exit code rather than `-1`. The timeout still applies underneath: a process that never prints a marker is killed at the deadline as before.

This is what makes a killed mutant cheap. A mutant is killed by its *first* failing test, and `TestOutputParser.parse` already reports only that one; running the remaining tests after it changed nothing but the clock. Neither XCTest nor Swift Testing offers a stop-on-first-failure switch, so the runner watches for one. Measured on `swift-cpd` (987 mutants, a suite that runs 14s alone), stopping early took a full run from 38m30s to 25m38s on its own, and 13m46s with the rest of the work in this area — the probe standing in for the baseline, the file's own tests running first, and incompatible mutants spread over warm sandboxes. The first 300 mutants ran three times faster than before; the middle of the run less so, which is where the killing tests are the slow integration ones and the first failure lands late regardless of order. It applies to the SPM test-bundle runs and the `swift test` fallback only; `xcodebuild test-without-building` is left to finish, because its verdict is read from the `.xcresult` bundle it writes at the end.

**Cancellation handling:** `onCancel` marks the flag and calls `onTimeout(pid)` immediately, ensuring the continuation is always resumed via the `terminationHandler`. A task that is already cancelled runs `onCancel` before the process exists, with pid 0, which signals nothing; `run` therefore checks for cancellation before `process.run()` (`Task.checkCancellation`) and resumes with `CancellationError` without starting anything, and checks again right after through `isCancelled`, so a cancellation that lands while the process starts still stops it through `onTimeout`. `isCancelled` defaults to `Task.isCancelled`; a test hands in one that answers `true` to make that window happen.

**Post-termination cleanup:** `postTerminationCleanup` is called after every process termination (success or failure), used by `SPMProcessLauncher` to kill the process group.

`launchCapturing` writes output to a temporary file (UUID-named) and reads it in the `terminationHandler` to avoid pipe buffer limits.

**Process groups:** Foundation's `Process` starts every child as the leader of a process group of its own, which is what lets `kill(-pid, …)` reach a whole test tree. The runner used to call `setpgid(pid, pid)` after `process.run()`, but by then the child has exec'd and the call always fails with `EACCES`. `checkOwnGroup(_:groupOf:warning:)` instead reads `getpgid(pid)` and, if a live process does not lead its own group, warns once on stderr through an `OnceWarning` that a timeout or an interrupt may leave its children running.

**Tracking what is in flight:** both launch paths register the new group in `processGroups` right after the group check, and the `terminationHandler` deregisters it first thing, so the signal handler in `SandboxCleaner` knows exactly which groups to kill if the tool is interrupted. A process that exits before it is registered would otherwise leave its pid behind — and a later `killAll` would signal whatever reused it — so registration is followed by an `isRunning` check that undoes it — `track(_:isRunning:in:)`, static so a test can pass a process that has already exited.

---

## Infrastructure/SPMProcessLauncher.swift

```swift
struct SPMProcessLauncher: Sendable, RunnerLaunching {
    static func terminate(pid: pid_t, escalation: TimeoutEscalation, kill: SystemCalls.Kill = Darwin.kill)
    func makeRunner() -> ProcessRunner
}
```

SPM-specific implementation of `ProcessLaunching`. `makeRunner()` creates a `ProcessRunner`, with a `TimeoutEscalation` of its own, with:
- `onTimeout`: `terminate(pid:escalation:)`, which does nothing for pid 0 and otherwise freezes the group with `SIGSTOP`, snapshots the process's descendants via `ProcessTree`, arms a `TimeoutEscalation`, and kills the descendants and then the group with `SIGKILL`
- `postTerminationCleanup`: kills the process group via `kill(-pid, SIGKILL)` and tells the escalation the process is gone

The group is frozen **before** the descendants are collected, and the snapshot is taken while the process that owns them is still alive to be traced back to. Freezing first is what makes the snapshot complete: a test process that is asked to stop but ignores or delays the signal can spawn another child in the meantime, and that grandchild — born after the snapshot, in its own process group if the shell enabled job control — survives every signal aimed at the group and at the pids that were listed. It then runs forever at 100% of a core with no parent to reap it. `SIGSTOP` cannot be caught, blocked or ignored, so nothing new is forked between the freeze and the kill.

`SIGKILL` rather than `SIGTERM` for the same reason: a test binary is not owed a chance to clean up after its deadline, and a handler that delays exit is a handler that delays the whole run. The `TimeoutEscalation` is still armed, now as the sweep for anything the snapshot missed rather than as the escalation from a polite signal. Cleanup that instead matched processes by sandbox name could not tell one mutant's run from another's when both ran in the same sandbox: it killed the next mutant's test binary, and the truncated output was read as a crash.

**`TimeoutEscalation`** — owns the SIGKILL that follows the first signals, and ties it to the run's lifetime. A process that stops when asked has its descendants cleaned up at once and the pending kill cancelled, rather than a timer firing seconds later when the pid may belong to something else.

---

## Infrastructure/XcodeProcessLauncher.swift

```swift
struct XcodeProcessLauncher: Sendable, RunnerLaunching {
    static func terminate(pid: pid_t, escalation: TimeoutEscalation, kill: SystemCalls.Kill = Darwin.kill)
    func makeRunner() -> ProcessRunner
}
```

The default launcher for Xcode projects. Its timeout handler, `terminate(pid:escalation:)`, is simpler than the SPM one: nothing for pid 0, otherwise `SIGTERM` to the group, then a `TimeoutEscalation` armed with no descendants for the `SIGKILL` after its grace period. When the process exits first, `postTerminationCleanup` cancels that kill and, if it was pending, kills what is left of the group at once — the delayed kill used to be a detached task that fired five seconds later whatever happened, on every killed mutant, at a pid that might by then lead someone else's group. There is no descendant snapshot — `xcodebuild` reaps its own children, and its results are read from the `.xcresult` bundle rather than from whatever the processes left on stdout.

---

## Infrastructure/SleepInhibitor.swift

```swift
enum SleepInhibitor {
    typealias AssertionTable = () -> NSDictionary?
    static let reason: String
    static func preventingIdleSleep<T>(reason: String = reason, _ body: () async throws -> T) async rethrows -> T
    static func isHeld(by pid: pid_t = getpid(), reason: String = reason, table: AssertionTable = assertionsByProcess) -> Bool
}
```

Holds an IOKit `PreventSystemSleep` assertion for as long as `body` runs, the same one `caffeinate -s` takes. The entry point wraps discovery and execution in it, so a run left unattended keeps going instead of pausing whenever the machine sleeps: with 15 test processes suspended mid-run, every one of them comes back past its timeout and the wall-clock time of the run grows by the length of the nap. `PreventUserIdleSystemSleep` (`caffeinate -i`) is not enough, because it only counts while the machine is fully awake; a machine that wakes briefly for maintenance goes straight back to sleep under it, and a mutation run can spend most of its life in exactly that state. Like `caffeinate -s`, the assertion only applies on AC power. `isHeld` reads the assertion table back and exists so tests can observe the assertion being taken and released. Both take the assertion's `reason`, because the table is per process: while one test checks that nothing is held, another may be running the whole pipeline in the same process and holding the default one. Tests pass a reason of their own.

---

## Infrastructure/StandardOutput.swift

```swift
enum StandardOutput {
    @TaskLocal static var capture: Capture?
    static func write(_ line: String = "")

    final class Capture: Sendable {
        var contents: String { get }
        func append(_ text: String)
    }
}
```

Everything the tool prints to stdout goes through `write`, which prints the line — or, when the current task has a `capture` bound, appends it there instead. Task-locals are inherited by child tasks, so a capture bound around a whole run sees what the reporters print from inside task groups.

It exists for the tests. They used to capture output by pointing file descriptor 1 at a pipe with `dup2`, which is process-wide: two tests doing it at once took each other's output, and when they finished in the wrong order one of them restored stdout to the other's pipe, so that pipe never saw end-of-file and the test waited on it forever. A capture bound to the task belongs to one test only.

---

## Infrastructure/StandardError.swift

```swift
enum StandardError {
    @TaskLocal static var capture: StandardOutput.Capture?
    static func write(_ line: String)
}
```

The stderr counterpart of `StandardOutput`: every warning and error the tool prints goes through `write`, which appends a newline and writes to stderr — or, when the current task has a `capture` bound, to that capture. No code calls `fputs(…, stderr)` directly, so a test can check a warning (the SARIF result limit, a report that could not be written) the same way it checks stdout.

---

## Infrastructure/FileSystem.swift

```swift
struct FileSystem: Sendable {
    var fileExists: @Sendable (String) -> Bool
    var directoryExists: @Sendable (String) -> Bool
    var contentsOfDirectory: @Sendable (String) -> [String]
    var currentDirectory: @Sendable () -> String
    var createDirectory: @Sendable (URL) throws -> Void
    var removeItem: @Sendable (String) -> Void

    func projectPath(_ path: String) -> String
}
```

The file-system calls that `ConfigurationResolver`, `ProjectDetector`, `XcodeContainerLocator` and `CacheStore` make, each defaulting to the real `FileManager` call; a test hands in a value with the closures it needs replaced. `contentsOfDirectory` answers `[]` and `removeItem` does nothing when the call fails. `projectPath(_:)` is the one place a project given as `.`, as an empty string or as a path becomes an absolute, standardized path: `.` and `""` are `currentDirectory()`.

---

## Infrastructure/VersionedJSON.swift

```swift
enum VersionedJSON {
    struct Failures {
        let notFound: any Error
        let unreadable: any Error
        let unsupported: (Int) -> any Error
    }

    static func read<Document: Decodable>(
        _: Document.Type, from path: String, version: Int, decoder: JSONDecoder = JSONDecoder(),
        failures: Failures
    ) throws -> Document
    static func encode(_ document: some Encodable, dates: JSONEncoder.DateEncodingStrategy = .deferredToDate) throws -> Data
    static func sha256(of data: Data) -> String
}
```

The format shared by `PlanStore` and `BaselineStore`. `read` decodes a document carrying a `formatVersion` in two steps — the version first, then the whole document — so a file written by another version is refused with the caller's `failures.unsupported` error rather than as unreadable; a missing file throws `failures.notFound`, and a file whose header or document does not decode `failures.unreadable`. An error reading a file that exists propagates as it is. The document type is passed unnamed, `read(Plan.self, from:…)`, and `decoder` lets `BaselineStore` decode ISO 8601 dates. `encode` produces the same bytes wherever it runs: pretty-printed, sorted keys, no escaped slashes, one trailing newline. `sha256(of:)` is the lowercase hex digest the stores hash those bytes with.

---

## Infrastructure/JSONLines.swift

```swift
enum JSONLines {
    static func append(_ value: some Encodable, to path: String) throws
    static func failureWarning(for path: String, error: any Error) -> String
    static func read<Value: Decodable>(_: Value.Type, from path: String) -> [Value]
}
```

A file of one JSON value per line, shared by `CacheStore`'s journal and `PlanJournal`. `append` encodes one value, creates the parent directory if needed and appends the line, so a run cut short keeps every line it wrote. It throws when any step fails — a full disk, a parent that is a file — and each journal reports that through an `OnceWarning` with `failureWarning(for:error:)`, once per journal, and goes on: the verdict is still in memory and reaches `results.json` and the reports, but would be lost to an interruption. Every step used to be a `try?`, so a full disk dropped entries without a word. `read` returns the values in order, skipping any line that does not decode — such as one an interruption left incomplete — and an empty array when the file does not exist or cannot be read. Its type parameter is passed unnamed, `read(Entry.self, from: path)`.

---

## Infrastructure/OnceWarning.swift

```swift
final class OnceWarning: Sendable {
    init(warn: @escaping @Sendable (String) -> Void = StandardError.write)
    func callAsFunction(_ message: @autoclosure () -> String)
}
```

Writes its first message through `warn` and ignores every later one, with an `Atomic<Bool>` so concurrent callers agree on which was first; the message is an autoclosure, so a later call does not even build it. Used for a warning that would otherwise repeat once per mutant: each `CacheStore` and `PlanJournal` takes one for its journal, and `ProcessRunner` keeps one for the process-group check.

---

## Infrastructure/OutputStopRule.swift

```swift
struct OutputStopRule: Sendable, Equatable {
    enum Line: Sendable, Equatable {
        case testFailure
    }

    static let firstTestFailure: OutputStopRule

    let line: Line
    let exitCode: Int32

    func matches(_ text: String) -> Bool
}
```

The kind of line that, once seen in a process's output, means there is no point letting it run on — and the exit code to report when that happens. `matches` looks at the text line by line. `.firstTestFailure` stops at a line `TestOutputParser.failingTest(in:)` names a failed test from, with exit code 1.

---

## Infrastructure/OutputWatcher.swift

```swift
struct OutputWatcher {
    init(url: URL, rule: OutputStopRule)

    mutating func sawMarker() -> Bool
}
```

Reads the capture file incrementally: each call starts where the last one stopped and keeps the trailing partial line, so a marker split across two writes is matched on the second look rather than missed. The bytes are decoded leniently, like the capture itself, and a file that cannot be opened, or has nothing new, answers `false`. Used by `ProcessRunner` while a request carries a stop rule.

---

## Infrastructure/SystemCalls.swift

```swift
enum SystemCalls {
    typealias Kill = @Sendable (pid_t, Int32) -> Int32
    typealias Sysctl = (
        UnsafeMutablePointer<Int32>?, UInt32, UnsafeMutableRawPointer?,
        UnsafeMutablePointer<Int>?, UnsafeMutableRawPointer?, Int
    ) -> Int32
}
```

The function types for the system calls this package injects, so a test can hand in one that fails. See **Regions the suite deliberately does not cover** in the [CodeBase index](README.md) for which calls take a parameter and why.

---

## Infrastructure/CanonicalPath.swift

```swift
enum CanonicalPath {
    typealias Resolver = (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

    static func make(for path: String, resolve: Resolver = { realpath($0, nil) }) -> String
}
```

Resolves symlinks with `realpath`, returning the input unchanged when it cannot. The sandbox lives under `$TMPDIR`, which is itself a symlink on macOS (`/var/folders/…` → `/private/var/folders/…`), and the compiler prints the resolved form; comparing paths without this is what made the build-retry parser miss every error it was given.

---

## Infrastructure/ProcessTree.swift

```swift
enum ProcessTree {
    static func descendants(of pid: Int32, sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32]
    static func isAlive(_ pid: pid_t) -> Bool
    static func all(sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32]
}
```

Walks the process table from `sysctl(KERN_PROC_ALL)` and returns every descendant of a pid, at any depth; a pid of 1 or below has none. Sizing the table and reading it are two calls, and processes started in between make the read fail with `ENOMEM`; the buffer therefore gets an eighth more room plus 16 entries, and a read that still fails with `ENOMEM` is retried from the sizing, up to three times, before the snapshot comes back empty. `SPMProcessLauncher.terminate` snapshots them while the group is frozen, so a test process that spawns children cannot leave one behind. `all()` returns every pid above 1, for `OrphanedProcessReaper` to inspect. `isAlive(_:)` is `kill(pid, 0)`, with `EPERM` counted as alive — the process exists, it is just not ours to signal; `SandboxName` and `CloneName` both decide ownership with it.

---

## Infrastructure/ProcessArguments.swift

```swift
enum ProcessArguments {
    static func read(pid: pid_t, sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [String]?
    static func parse(_ buffer: [UInt8]) -> [String]?
}
```

Reads another process's `argv` through `sysctl(KERN_PROCARGS2)`. The buffer holds `argc` as an `Int32`, the executable path, NUL padding, the `argc` arguments and then the environment. `parse` returns only the arguments. `read` returns `nil` when the kernel refuses, which is the case for other users' processes.

---

## Infrastructure/TimeoutEscalation.swift

```swift
final class TimeoutEscalation: @unchecked Sendable {
    init(gracePeriod: Double = 5, kill: @escaping SystemCalls.Kill = Darwin.kill)

    func arm(pid: Int32, descendants: [Int32])
    @discardableResult func processTerminated() -> Bool
}
```

Owns the `SIGKILL` that sweeps up whatever the first round of signals missed, and ties it to the run's lifetime: a process that stops when asked has its snapshotted descendants killed at once and the pending task cancelled, rather than a timer firing seconds later when the pid may belong to something else. Arming again cancels the kill already pending, and an arm after `processTerminated` does nothing. `processTerminated` reports whether a kill was pending, which is how `XcodeProcessLauncher` knows the process ended after a timeout.

---

## Infrastructure/ProcessGroupRegistry.swift

```swift
final class ProcessGroupRegistry: @unchecked Sendable {
    static let shared: ProcessGroupRegistry
    init(capacity: Int = 256)

    func register(_ pid: pid_t)
    func deregister(_ pid: pid_t)
    func killAll(kill: SystemCalls.Kill = Darwin.kill)
}
```

The process groups of the test runs currently in flight. `killAll` sends `SIGKILL` to each group and empties the registry; `SandboxCleaner.terminate` calls it from the signal handler, so the registry holds no lock and allocates nothing after `init`. Each slot is an `Atomic<pid_t>` claimed with one compare-exchange and released with another, which leaves a signal that lands mid-update seeing either the pid or an empty slot. `killAll` does not walk `ProcessTree` for descendants the way a timeout does: `sysctl` allocates, and the group kill already reaches every process the test run did not move into a group of its own.

The capacity bounds how many runs can be tracked at once — 256, well above the one SPM worker or the simulator pool's `CPUs - 1`. A run registered past it is simply not tracked, which is the behaviour every run had before this.

---

## Infrastructure/XCTestRunPlist.swift

```swift
struct XCTestRunPlist: Sendable, Equatable {
    typealias PlistSerializer = ([String: Any]) throws -> Data
    init?(_ data: Data)
    func activating(_ mutantID: String, activationFile: String? = nil, serialize: PlistSerializer = …) -> Data
}
```

Wraps the raw plist `Data` from the `.xctestrun` file; `init?` refuses data that is not a property-list dictionary.

`activating(_:activationFile:)` merges `TestBundleInvocation.environment(mutantID:activationFile:)` — `__SWIFT_MUTATION_TESTING_ACTIVE` set to `mutantID`, and the activation marker's variable when a file is given — into `EnvironmentVariables` for every test target in the plist. Handles both the `TestConfigurations` format (Xcode 15+) and the legacy flat dictionary format. Returns a fresh XML plist `Data` — the original is not mutated; when `serialize` fails it returns the original data.

---

## Infrastructure/ProjectRelativePath.swift

```swift
enum ProjectRelativePath {
    static func make(for path: String, in projectPath: String) -> String

    struct Resolver: Sendable {
        init(projectPath: String)
        func make(for path: String) -> String
    }
}
```

Turns an absolute path into one relative to the project root, resolving symlinks on both sides first so a sandbox path and a project path can be compared at all. A path outside the root, or the root itself, is returned unchanged. `make(for:in:)` builds a `Resolver` for one path. `Resolver` resolves the root once and relativizes any number of paths against it; the JSON, HTML, Sonar and SARIF reports, `MutantIndexingStage`, `Baseline` and `TestFilesHasher` take one per call instead of resolving the root again for every mutant. Every reporter uses it, which is why a mutant's file reads the same in the console, the JSON and the Sonar report no matter which sandbox produced it.

---

## Infrastructure/TestFilesHasher.swift

```swift
struct TestFilesHasher: Sendable {
    typealias FileEnumerator = (URL) -> FileManager.DirectoryEnumerator?
    static func defaultEnumerator(_ directory: URL) -> FileManager.DirectoryEnumerator?

    struct Snapshot: Sendable { let paths: [String]; let contents: [String: String]; let hashes: [String: String] }

    func snapshot(projectPath: String, enumerate: FileEnumerator = Self.defaultEnumerator) -> Snapshot
}
```

Lists and hashes the test files for granular cache invalidation. `defaultEnumerator` walks the project with `FileManager.enumerator(at:)`, skipping hidden files; a test passes another, such as one that answers `nil`.

| Method | Description |
|---|---|
| `snapshot(projectPath:enumerate:)` | Lists the test files once and reads each once: `paths` in enumeration order, `contents` by absolute path for the files that read as text, `hashes` mapping each readable file's relative path to its SHA256 content hash (a symlink pointing outside the project root keeps its absolute path as key, to avoid collisions). `MutantExecutor` takes one per run and builds the cache invalidation, the `KillerTestFileResolver` index and the targeted suites from it; it used to list the tree twice and read every test file three times |

**Test file collection:** Swift files under a directory whose name ends with `Tests`, or whose filename matches `*Tests.swift`. Only the directories between the project root and the file count — the path is made relative with `ProjectRelativePath` first — so a project checked out under, say, `~/Work/IntegrationTests/App` does not have every file taken for a test file.

---

## Infrastructure/Uniquing.swift

```swift
enum Uniquing {
    static func keepingFirst<Key: Hashable, Value>(_ pairs: some Sequence<(Key, Value)>) -> [Key: Value]
    static func keepingLast<Key: Hashable, Value>(_ pairs: some Sequence<(Key, Value)>) -> [Key: Value]
}
```

Builds a dictionary from key-value pairs that may repeat a key, keeping the first or the last value for it. `keepingFirst` serves the lookups by path or key — `MutantIndexingStage`, `SandboxFactory`, `TestBundleInvocation`'s environment, `PlanMaterializer` and `PlanJournal`'s fingerprints — and `keepingLast` reads `PlanJournal`'s entries, where the latest line wins. Both are plain loops rather than `Dictionary(_:uniquingKeysWith:)` with a function: a function passed as an argument compiles to a thunk that only runs on a duplicate key, which is a region no ordinary input covers (see **Regions the suite deliberately does not cover** in the [CodeBase index](README.md)).

---

← [Result Parsing & Cache](08-result-parsing-cache.md) | Next: [Quality Gate →](10-quality-gate.md)
