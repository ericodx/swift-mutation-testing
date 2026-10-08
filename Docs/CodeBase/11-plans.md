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
    let project: Project
    let scope: Scope
    let files: [File]
    let mutants: [Mutant]

    struct Project: Sendable, Codable, Equatable {
        let type: String
        let scheme: String?
        let destination: String?
        let testTarget: String?
        var workspace: String?
        var xcodeProject: String?
        init(type: ProjectType, testTarget: String?, container: XcodeContainer? = nil)
        var xcodeContainer: XcodeContainer? { get }
        var projectType: ProjectType? { get }
    }

    struct Scope: Sendable, Codable, Equatable {
        let sourcesPath: String
        let excludePatterns: [String]
        let operators: [String]
    }

    struct File: Sendable, Codable, Equatable {
        let path: String
        let sha256: String
    }

    struct Mutant: Sendable, Codable, Equatable {
        let fingerprint: String
        let file: String
        let utf8Start: Int
        let utf8End: Int
        let line: Int
        let column: Int
        let operatorIdentifier: String
        let replacementKind: ReplacementKind
        let original: String
        let replacement: String
        let description: String
        let schematizable: Bool
    }
}
```

`Project.type` is `spm` or `xcode`; `scheme` and `destination` are set for Xcode only, and `workspace` or `xcodeProject` names the Xcode container when one was given, read back as `xcodeContainer`. `Scope` holds paths relative to the project — no absolute path anywhere in the plan. `files` is every source file in scope, in path order, with the hash of its content; `mutants` holds every mutant's position as UTF-8 offsets as well as line and column.

In Swift the mutant's operator is `Mutant.operatorIdentifier`, encoded under the key `operator` so the plan's bytes, and its hash, stay the same. `Project.projectType` turns the strings back into a `ProjectType`, `nil` for a type this version does not know or an `xcode` plan without a scheme and destination. The mutant at index `i` of `mutants` has the report id `MutantID.make(index: i)` (`swift-mutation-testing_<i>`), the same id a plain run gives it, since both order mutants by file and offset. `MutantID` (`Discovery/Pipeline/MutantID.swift`) owns the format; `MutantID.index(of:)` reads it back and `MutantID.ordered(_:by:)` sorts by it.

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

```swift
enum PlanError: Error, Equatable, LocalizedError {
    case notFound(path: String)
    case unreadable(path: String)
    case unsupportedVersion(path: String, version: Int)
    case unknownProjectType(String)
    case stale(file: String)
    case missingFile(file: String)
    case unreadableFile(file: String, reason: String)
    case corrupt(fingerprint: String, file: String)
    case invalidShard(String)
    case unknownMutant(String)
}
```

Each with a message that says what to do: make the plan again for a stale, missing or unknown-version plan, `plan --output <path>` for one that does not exist, and an example id for an unknown mutant. `unreadableFile` carries the reason the file system gave.

## Plan/Planner.swift

```swift
struct Planner: Sendable {
    struct Planned { let plan: Plan; let sources: [ParsedSource] }
    func plan(input: DiscoveryInput, testTarget: String? = nil, container: XcodeContainer? = nil) async throws -> Planned
    static func relative(_ path: String, to projectPath: String) -> String
}
```

`FileDiscoveryStage` → `ParsingStage` → `MutantDiscoveryStage` (with `OperatorRegistry.operators(named:)`) → `MutantIndexingStage`, then the plan: files with `MutantCacheKey.hash` of their content, sorted by path, mutants from the indexed points with `utf8End` = `utf8Start` + the original text's UTF-8 length, and the scope's operators all of `OperatorRegistry.allOperatorNames` when none was selected. The parsed sources come out too, for the direct flow. The commands call it through `plan(for: RunnerConfiguration)` in `CLI/CommandSupport.swift`. `relative` is `ProjectRelativePath.make`, with `"."` for the root itself, both compared after resolving symlinks.

## Plan/PlanMaterializer.swift

```swift
struct PlanMaterializer: Sendable {
    struct ExecutionOptions { let timeout: Double; let concurrency: Int; let noCache: Bool }
    func materialize(plan: Plan, projectPath: String, execution: ExecutionOptions,
                     mutants selection: [Plan.Mutant]? = nil) async throws -> RunnerInput
    func materialize(plan: Plan, projectPath: String, sources: [ParsedSource],
                     execution: ExecutionOptions, mutants selection: [Plan.Mutant]? = nil) throws -> RunnerInput
    func load(plan: Plan, projectPath: String) throws -> [SourceFile]
    static func fileHashes(of plan: Plan) -> [String: String]
    static func descriptor(of mutant: Plan.Mutant, at index: Int, in plan: Plan, projectPath: String) -> MutantDescriptor
    static func descriptor(of mutant: Plan.Mutant, at index: Int, fileHashes: [String: String],
                           projectPath: String) -> MutantDescriptor
    static func absolute(_ relativePath: String, in projectPath: String) -> String
}
```

The first form reads the plan's files from disk through `load` — which throws `missingFile` for a file that is gone, `unreadableFile` with the reason for one that is there but cannot be read as UTF-8 text, `stale` on any hash that differs and `corrupt` on a mutant whose text is not at its range, each file's bytes copied once for every mutant of it — parses them and calls the second. The second rebuilds an `IndexedMutationPoint` per selected mutant (index = position in the plan; the file path taken from the matching source, matched by relative path with `Uniquing.keepingFirst`, so later lookups by path agree; `missingFile` when no source matches), runs `SchematizationStage` and `IncompatibleRewritingStage`, and assembles the `RunnerInput` with `ImportStyle.of(sources)`, its descriptors in id order (`MutantID.ordered`); a project type the plan cannot name throws `unknownProjectType`. `descriptor` rebuilds one plan mutant's `MutantDescriptor` without parsing anything, for the verdicts `PlanResumer` and `ResultMerger` take from a journal or a report: its id from the index, its path made absolute, no mutated source, and the file's plan hash as `sourceContentHash`, so the cache key matches the one a run computes. The `fileHashes:` form takes the `[path: sha256]` table `fileHashes(of:)` builds (`Uniquing.keepingFirst` over `plan.files`), so a loop over the plan's mutants builds it once instead of searching `plan.files` for each mutant; the `in:` form builds the table for a single call. `absolute` uses the root's real path (`CanonicalPath`), the way the file enumerator reports paths.

`DiscoveryPipeline.run` and a plain `run` are `Planner` then the second form; `run --plan` is `PlanStore.read` then the first, through `PlanResumer`. `ExecutionOptions(_ configuration:)` in `CLI/CommandSupport.swift` builds the options from a configuration.

## Plan/Shard.swift

```swift
struct Shard: Sendable, Equatable, CustomStringConvertible {
    let index: Int
    let count: Int
    init?(parsing raw: String)
    init(index: Int, count: Int)
    var description: String { get }
}

enum ShardSelector {
    static func files(of plan: Plan, in shard: Shard) -> [String]
    static func mutants(of plan: Plan, in shard: Shard) -> [Plan.Mutant]
}
```

`init?(parsing:)` reads `i/n` with `1 ≤ i ≤ n` and is `nil` for anything else; `description` writes it back. `ShardSelector` takes the files that hold mutants in path order, each to the shard with the fewest mutants so far, ties to the lowest index; `mutants(of:in:)` is the plan's mutants in those files, in plan order.

## Plan/PlanJournal.swift

```swift
struct PlanJournal: Sendable {
    struct Entry: Sendable, Codable, Equatable {
        let fingerprint: String
        let status: ExecutionStatus
        let killerTestFile: String?
        let activated: Bool?
        let duration: Double
    }

    let path: String
    init(path: String, mutants: [MutantDescriptor], warning: OnceWarning = OnceWarning())
    static func path(projectPath: String, planSha256: String, shard: Shard?) -> String
    func record(
        status: ExecutionStatus, for key: MutantCacheKey, killerTestFile: String?, activated: Bool?, duration: Double
    )
    static func entries(at path: String) -> [String: Entry]
    static func remove(at path: String)
}
```

The progress of one run of a plan or shard, at `<project>/.swift-mutation-testing-cache/plans/<planSha256>.jsonl`, or `<planSha256>-<i>-of-<n>.jsonl` for a shard. `init` maps each mutant's cache key to its fingerprint, the first mutant winning a key two share. `record` looks the cache key up — a key of no mutant given at init records nothing — and appends one line with `JSONLines.append`, warning once through `warning` if the line cannot be written; `entries` reads them back with `JSONLines.read`, keyed by fingerprint, the last line winning (`Uniquing.keepingLast`) and a cut-short line skipped. `MutantExecutor(configuration:launcher:planJournal:)` hands it to `CacheStore`, whose `store(…, duration:)` records into it before its `noCache` and timeout guards. `PlanResumer` reads it for `run --plan`; `RunCommand` removes it when it has its results.

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

The input of `run --plan`. `discover` computes the `RunIdentity` (plan hash and shard), selects the shard's mutants (`ShardSelector`) or all of them, reads the journal at `PlanJournal.path(…)`, and materializes only the selected mutants with no journaled verdict. The journaled ones of the selection come back in `resumed` as `ExecutionResult`s — the descriptor rebuilt from the plan, the status, duration, killer test file and activation from the entry — and `journal` is a new `PlanJournal` over the materialized mutants for the run to record into. `RunCommand` builds a `Discovered` itself for a plain run, with nothing resumed and no journal.

## Plan/RunIdentity.swift

```swift
struct RunIdentity: Sendable, Equatable { let planSha256: String; let shard: Shard? }
```

What `JsonReporter` writes under `config`. Every run has one.

## Plan/RunnerConfiguration+Plan.swift

```swift
extension RunnerConfiguration {
    func applying(_ plan: Plan) throws -> RunnerConfiguration
}
```

The project type, test target, Xcode container and scope from the plan — the sources path made absolute with `PlanMaterializer.absolute` — and everything else untouched; a project type the plan cannot name throws `PlanError.unknownProjectType`. Used by `run --plan`, `merge` and `reproduce --plan` — through `applyingPlan(at:)` in `CLI/CommandSupport.swift`, which reads the plan and applies it — before the baseline is loaded, so the gate's scope is the plan's.

## Plan/ResultMerger.swift and Plan/MergeError.swift

```swift
struct ResultMerger: Sendable {
    struct Merged: Sendable {
        let results: [ExecutionResult]
        let totalDuration: Double
        let planSha256: String
    }

    func merge(resultPaths: [String], plan: Plan, projectPath: String) throws -> Merged
}

enum MergeError: Error, Equatable, LocalizedError {
    case unreadableResult(path: String)
    case noIdentity(path: String)
    case differentPlan(path: String)
    case duplicate(fingerprint: String, paths: [String])
    case missing(count: Int, sample: [String])
    case unknownStatus(path: String, status: String)
}
```

Decodes each report as `MutationReportPayload` (`unreadableResult` when it cannot), refuses one without `config` (`noIdentity`) or whose `config.planSha256` is not the plan's (`differentPlan`), and a fingerprint seen twice (`duplicate`, naming both files). One pass over the plan's mutants then pairs each with its verdict and collects the ones with none (`missing`, with the first five named as fingerprint, file and line). Each pair becomes an `ExecutionResult`: the descriptor from the plan, the status from the report's `status` — `Killed` with a `killedBy` is `.killed(by:)`, without one `.killedByCrash`; a status the schema mapping does not produce is `unknownStatus` — the activation from `activated`, the duration from `duration` in milliseconds. `totalDuration` is the sum of the test durations. `planSha256` is the hash it checked the reports against, so `MergeCommand` does not encode the whole plan a second time for the merged report's identity.

## Plan/Reproducer.swift

```swift
struct Reproducer: Sendable {
    func reproduce(_ reference: String, plan: Plan, configuration: RunnerConfiguration,
                   launcher: any ProcessLaunching) async throws -> ExitCode
    static func verdict(of results: [ExecutionResult]) -> (line: String, exit: ExitCode)
    static func mutant(matching reference: String, in plan: Plan) throws -> (Int, Plan.Mutant)
    static func diff(of mutant: Plan.Mutant, in projectPath: String) -> String
}
```

Sets `build.reproduction` to a new `Reproduction`, `noCache`, one worker and `quiet`, keeps the logs — in `--keep-logs` when given, else in a directory per fingerprint under the temporary directory — materializes the one mutant, runs `MutantExecutor`, then prints the kept sandboxes, the diff, the mutant's log and the verdict. `mutant(matching:)` takes a report id (read with `MutantID.index(of:)`), a full fingerprint, or a prefix of at least six characters that fits exactly one mutant; anything else is `PlanError.unknownMutant`. `diff(of:in:)` applies the mutation with `MutationRewriter` and prints each changed line before and after, or the bare mutation when the file cannot be read. `verdict(of:)` describes the first result with its status reason and exits `.success`; no result at all exits `.error`.

`build.reproducing` — `reproduction != nil` — is read in `TestExecutionStage` and `IncompatibleMutantExecutor` (no targeted-suite run, no stop rule on the requests) and in `IncompatibleMutantExecutor.runXcode` (the cold path, a sandbox per attempt). The executors release their sandboxes through `Sandbox.release(keepingFor: configuration.build.reproduction)`, which keeps them for a reproduction — all but the warm Xcode workers of `IncompatibleMutantExecutor`, which only run outside a reproduction and release with `nil`.

## Plan/Reproduction.swift

```swift
final class Reproduction: Sendable {
    var keptSandboxes: [String] { get }
    func keep(_ sandbox: Sandbox)
}

extension Sandbox {
    func release(keepingFor reproduction: Reproduction?)
}
```

What a reproduction keeps. `release(keepingFor:)` is how every executor lets go of a sandbox: with a `Reproduction` it records the sandbox's root path instead of removing it, and without one it calls `cleanup()`. `keep` appends under a `Mutex`, since the executors release from concurrent tasks; `Reproducer` prints `keptSandboxes` once the run is over. It replaced a `reproducing` flag, after which the reproducer listed every sandbox its own process owned in the sandbox directory — sandboxes it had not kept among them.
