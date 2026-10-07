# Plans

← [Quality Gate](10-quality-gate.md) | [Index →](README.md)

---

The `Plan/` directory holds the plan, the two halves of discovery around it, the shards, the merge and the reproducer. The reasoning is in [Architecture — Plans](../Architecture/06-plans.md).

## Plan/Plan.swift

```swift
struct Plan: Sendable, Codable, Equatable {
    static let formatVersion = 1
    let formatVersion: Int
    let toolVersion: String
    let project: Project       // type ("spm" | "xcode"), scheme, destination, testTarget
    let scope: Scope           // sourcesPath, excludePatterns, operators — relative, no absolute path
    let files: [File]          // path, sha256 — every source file in scope, in path order
    let mutants: [Mutant]      // fingerprint, file, utf8Start, utf8End, line, column, operator,
                               // replacementKind, original, replacement, description, schematizable
}
```

In Swift the mutant's operator is `Mutant.operatorIdentifier`, encoded under the key `operator` so the plan's bytes, and its hash, stay the same. `Project.projectType` turns the strings back into a `ProjectType`, `nil` for a type this version does not know. The mutant at index `i` of `mutants` has the report id `MutantID.make(index: i)` (`swift-mutation-testing_<i>`), the same id a plain run gives it, since both order mutants by file and offset. `MutantID` (`Discovery/Pipeline/MutantID.swift`) owns the format; `MutantID.index(of:)` reads it back and `MutantID.ordered(_:by:)` sorts by it.

## Plan/PlanStore.swift

```swift
struct PlanStore: Sendable {
    func read(from path: String) throws -> Plan
    func write(_ plan: Plan, to path: String) throws
    static func encode(_ plan: Plan) throws -> Data
    static func sha256(of plan: Plan) throws -> String
}
```

`read` is `VersionedJSON.read`, shared with `BaselineStore`: it checks the `formatVersion` header first and throws `PlanError.notFound`, `.unreadable` or `.unsupportedVersion`. `encode` is `VersionedJSON.encode` — sorted keys, no escaped slashes, a trailing newline — and `sha256(of:)` is `VersionedJSON.sha256` over those bytes, the plan's identity.

## Plan/PlanError.swift

`notFound`, `unreadable`, `unsupportedVersion`, `unknownProjectType`, `stale(file:)`, `missingFile(file:)`, `corrupt(fingerprint:file:)`, `invalidShard`, `unknownMutant` — each with a message that says what to do.

## Plan/Planner.swift

```swift
struct Planner: Sendable {
    struct Planned { let plan: Plan; let sources: [ParsedSource] }
    func plan(input: DiscoveryInput, testTarget: String? = nil, container: XcodeContainer? = nil) async throws -> Planned
    static func relative(_ path: String, to projectPath: String) -> String
}
```

`FileDiscoveryStage` → `ParsingStage` → `MutantDiscoveryStage` (with `OperatorRegistry.operators(named:)`) → `MutantIndexingStage`, then the plan: files with `MutantCacheKey.hash` of their content, mutants from the indexed points. The parsed sources come out too, for the direct flow. The commands call it through `plan(for: RunnerConfiguration)` in `CLI/CommandSupport.swift`. `relative` is `ProjectRelativePath.make`, with `"."` for the root itself.

## Plan/PlanMaterializer.swift

```swift
struct PlanMaterializer: Sendable {
    struct ExecutionOptions { let timeout: Double; let concurrency: Int; let noCache: Bool }
    func materialize(plan: Plan, projectPath: String, execution: ExecutionOptions,
                     mutants selection: [Plan.Mutant]? = nil) async throws -> RunnerInput
    func materialize(plan: Plan, projectPath: String, sources: [ParsedSource],
                     execution: ExecutionOptions, mutants selection: [Plan.Mutant]? = nil) throws -> RunnerInput
    func load(plan: Plan, projectPath: String) throws -> [SourceFile]
    static func absolute(_ relativePath: String, in projectPath: String) -> String
}
```

The first form reads the plan's files from disk through `load` — which throws `stale` or `missingFile` on any hash that differs and `corrupt` on a mutant whose text is not at its range — parses them and calls the second. The second rebuilds an `IndexedMutationPoint` per selected mutant (index = position in the plan; the file path taken from the matching source, matched by relative path, so later lookups by path agree), runs `SchematizationStage` and `IncompatibleRewritingStage`, and assembles the `RunnerInput` with `ImportStyle.of(sources)`, its descriptors in id order (`MutantID.ordered`). `absolute` uses the root's real path (`CanonicalPath`), the way the file enumerator reports paths.

`DiscoveryPipeline.run` and a plain `run` are `Planner` then the second form; `run --plan` is `PlanStore.read` then the first, through `PlanResumer`. `ExecutionOptions(_ configuration:)` in `CLI/CommandSupport.swift` builds the options from a configuration.

## Plan/Shard.swift

```swift
struct Shard: Sendable, Equatable, CustomStringConvertible {
    init?(parsing raw: String)            // "i/n", 1 ≤ i ≤ n
    init(index: Int, count: Int)
}

enum ShardSelector {
    static func files(of plan: Plan, in shard: Shard) -> [String]
    static func mutants(of plan: Plan, in shard: Shard) -> [Plan.Mutant]
}
```

Files in path order, each to the shard with the fewest mutants so far, ties to the lowest index.

## Plan/PlanJournal.swift

```swift
struct PlanJournal: Sendable {
    struct Entry: Codable, Equatable { let fingerprint: String; let status: ExecutionStatus
                                       let killerTestFile: String?; let activated: Bool?; let duration: Double }
    init(path: String, mutants: [MutantDescriptor], warning: OnceWarning = OnceWarning())
    static func path(projectPath: String, planSha256: String, shard: Shard?) -> String
    func record(status:for:killerTestFile:activated:duration:)
    static func entries(at path: String) -> [String: Entry]
    static func remove(at path: String)
}
```

The progress of one run of a plan or shard. `record` maps the cache key to the mutant's fingerprint and appends one line with `JSONLines.append`, warning once through `warning` if the line cannot be written; `entries` reads them back with `JSONLines.read`, the last line winning and a cut-short line skipped. `MutantExecutor(configuration:launcher:planJournal:)` hands it to `CacheStore`, whose `store(…, duration:)` records into it before its `noCache` and timeout guards. `PlanResumer` reads it for `run --plan`; `RunCommand` removes it when it has its results.

## Plan/PlanResumer.swift

```swift
struct PlanResumer: Sendable {
    let plan: Plan
    let shard: Shard?

    struct Discovered {
        let input: RunnerInput
        let identity: RunIdentity
        let duration: TimeInterval
        var resumed: [ExecutionResult] = []
        var journal: PlanJournal?
    }

    func discover(configuration: RunnerConfiguration) async throws -> Discovered
}
```

The input of `run --plan`. `discover` computes the `RunIdentity` (plan hash and shard), selects the shard's mutants (`ShardSelector`) or all of them, reads the journal at `PlanJournal.path(…)`, and materializes only the mutants with no journaled verdict. The journaled ones come back in `resumed` as `ExecutionResult`s — the descriptor rebuilt from the plan, the status, duration, killer test file and activation from the entry — and `journal` is a new `PlanJournal` over the materialized mutants for the run to record into. `RunCommand` builds a `Discovered` itself for a plain run, with nothing resumed and no journal.

## Plan/RunIdentity.swift

```swift
struct RunIdentity: Sendable, Equatable { let planSha256: String; let shard: Shard? }
```

What `JsonReporter` writes under `config`. Every run has one.

## Plan/RunnerConfiguration+Plan.swift

`RunnerConfiguration.applying(_ plan:)`: the project type, test target and scope from the plan; everything else untouched. Used by `run --plan`, `merge` and `reproduce --plan` — through `applyingPlan(at:)` in `CLI/CommandSupport.swift`, which reads the plan and applies it — before the baseline is loaded, so the gate's scope is the plan's.

## Plan/ResultMerger.swift and Plan/MergeError.swift

```swift
struct ResultMerger: Sendable {
    struct Merged { let results: [ExecutionResult]; let totalDuration: Double }
    func merge(resultPaths: [String], plan: Plan, projectPath: String) throws -> Merged
}
```

Decodes each report as `MutationReportPayload`, checks `config.planSha256` against the plan, refuses a fingerprint seen twice (`MergeError.duplicate`) and a plan mutant seen never (`.missing`, with the first five named), and rebuilds an `ExecutionResult` per plan mutant: the descriptor from the plan, the status from the report's `status`, `killedBy` and `statusReason`, the activation from `activated`, the duration from `duration`.

## Plan/Reproducer.swift

```swift
struct Reproducer: Sendable {
    func reproduce(_ reference: String, plan: Plan, configuration: RunnerConfiguration,
                   launcher: any ProcessLaunching) async throws -> ExitCode
    static func mutant(matching reference: String, in plan: Plan) throws -> (Int, Plan.Mutant)
}
```

Sets `build.reproducing`, `noCache` and one worker, materializes the one mutant, runs `MutantExecutor`, then prints the kept sandboxes, the diff, the log and the verdict. `mutant(matching:)` takes a report id (read with `MutantID.index(of:)`), a full fingerprint, or a prefix of at least six characters that fits exactly one mutant.

`build.reproducing` is read in `TestExecutionStage` (no targeted-suite run, no stop rule on the requests) and in the three executors' `defer` blocks (the sandbox is not removed).
