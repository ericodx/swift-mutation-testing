# Execution

← [Sandbox & Build](06-sandbox-build.md) | Next: [Result Parsing & Cache →](08-result-parsing-cache.md)

---

## Execution/MutantExecutor.swift

```swift
struct MutantExecutor: Sendable {
    struct Environment: Sendable {
        var sandboxFactory = SandboxFactory()
        var verifier = ApplicationVerifier()
        var testFilesHasher = TestFilesHasher()
        var reporter: (any ProgressReporter)?
    }

    init(
        configuration: RunnerConfiguration,
        launcher: any ProcessLaunching,
        planJournal: PlanJournal? = nil,
        environment: Environment = Environment()
    )
    func execute(_ input: RunnerInput) async throws -> [ExecutionResult]
}
```

Entry point for the execution pipeline. Orchestrates sandbox creation, build, simulator pool setup, and test execution for both schematizable and incompatible mutants. Supports both Xcode and SPM project types.

`Environment` holds the collaborators a run works through, each the real one unless a test hands in another. With no `reporter`, progress goes to a `ConsoleProgressReporter`, or a `SilentProgressReporter` under `--quiet`. The `sandboxFactory` is also the one `IncompatibleMutantExecutor` is given.

The work that used to live inline here is split across types of its own: `SchemaNarrower` retries a schematized SPM build that does not compile, `BaselineProbe` runs the unmutated suite, `SimulatorPool.make(for:launcher:)` picks the pool, and every verdict goes through `ResultRecorder`. `execute` itself only prepares the cache, returns early when every mutant is cached, builds the `ExecutionDeps` — `TargetedSuites.declared(in:read:)` over the test files the cache snapshot already read — creates and registers the sandbox, and persists the cache; the private `run(_:in:deps:reporter:)` verifies the sandbox, builds, sets up the pool, runs every mutant and checks activation, tearing the pool down whether it throws or not. The sandbox is released in a `defer` through `release(keepingFor:)`, which keeps it for a reproduction.

```mermaid
flowchart TD
    IN["RunnerInput"] --> PREP["prepareCacheStore<br>granular invalidation"]
    PREP --> CACHE{"all results cached?"}
    CACHE -- yes --> RETURN["return cached results"]
    CACHE -- no --> DEPS["makeExecutionDeps<br>TargetedSuites.declared"]
    DEPS --> SANDBOX["SandboxFactory.create<br>schematized sandbox"]
    SANDBOX --> REG["SandboxCleaner.register"]
    REG --> VERIFY["ApplicationVerifier.verify"]
    VERIFY -- "a mutant is missing" --> ABORTI["throw IntegrityError<br>run ends"]
    VERIFY -- "every mutant present" --> BUILD["BuildStage.build / buildSPM"]
    BUILD -- success --> POOL["SimulatorPool.make, setUp<br>report workersReady"]
    BUILD -- timedOut --> ABORT["throw BuildError<br>run ends"]
    BUILD -- "compilationFailed, Xcode" --> POOL
    BUILD -- "compilationFailed, SPM" --> RETRY["SchemaNarrower.narrow<br>regenerate the schema without<br>the mutants the compiler blamed"]
    RETRY -- "rebuilt, or nothing to exclude" --> POOL
    POOL --> ART{"build artifact?"}
    ART -- "none, schematizable mutants left" --> FALLBACK["FallbackExecutor<br>one build per schematized file"]
    ART -- yes --> PROBE{"SPM: BaselineProbe runs each<br>testing library once on the<br>unmutated sandbox"}
    PROBE -- "a library fails, crashes or hangs" --> ABORTB["throw BaselineError<br>run ends"]
    PROBE -- "passes, or Xcode" --> NORMAL["TestExecutionStage<br>schematizable mutants"]
    NORMAL --> INCOMPAT["IncompatibleMutantExecutor<br>incompatible and rerouted mutants"]
    FALLBACK --> INCOMPAT
    ART -- "none, nothing left" --> INCOMPAT
    INCOMPAT --> OBSERVED{"kills, but no mutant's<br>code ever seen running?"}
    OBSERVED -- yes --> ABORTI
    OBSERVED -- no --> TEARDOWN["pool.tearDown<br>sandbox.release(keepingFor:)<br>SandboxCleaner.deregister<br>cacheStore.persist"]
    TEARDOWN --> RESULTS[["[ExecutionResult]"]]
```

**Baseline validation (SPM only):** before any mutant runs, `BaselineProbe` runs the suite once with no mutant selected — the schema falls through to its `default` branch, so this is the original code. A kill verdict only means something if the same tests pass unmutated: a suite that already fails kills every mutant it reaches and produces a flattering score with nothing in the report to show it. Anything other than a passing suite throws `BaselineError` and ends the run. The Xcode path has no equivalent yet.

**Normal path:** builds once, runs `TestExecutionStage` for all schematizable mutants in parallel, then re-runs any mutant that timed out on its own before reporting it.

**Fallback path:** triggered when `BuildStage` throws `compilationFailed` on the Xcode path, or on the SPM path when `SchemaNarrower` finds no mutant to blame, and only when schematizable mutants remain besides the ones narrowing took out. Delegates to `FallbackExecutor`, which rebuilds one schematized file at a time. Mutants in files that still fail to compile are marked `.unviable`. The fallback gets `input.excluding(_:)` with the ids narrowing took out: those mutants already go to the incompatible path, and before this each of them got a second verdict from the fallback.

**Incompatible path:** always runs after the schematizable path. Delegates to `IncompatibleMutantExecutor`. Mutants `SchemaNarrower` took out of the schema join it, rewritten with `MutationRewriter` from the original file; one whose rewrite leaves the source unchanged is recorded `.unviable` through `ResultRecorder`.

**Integrity:** `ApplicationVerifier` runs right after the sandbox is created and before anything is built, and `requireObservedActivation(in:)` runs over the results: when at least one measured mutant was killed and no measured mutant recorded activation, the run ends with `IntegrityError.activationNeverObserved` — the marker cannot be written here, or the suite fails on its own, and either way no verdict can be trusted. Both are static so a test can call them on their own.

---

## Execution/SchemaNarrower.swift

```swift
struct SchemaNarrower: Sendable {
    let stage: BuildStage
    let reporter: any ProgressReporter
    let buildTimeout: Double

    func narrow(
        after output: String,
        sandbox: Sandbox,
        input: RunnerInput,
        start: Date,
        alreadyExcluded: [MutantDescriptor] = []
    ) async throws -> (BuildArtifact?, [MutantDescriptor])

    static func excludeProblematicMutants(
        sandboxPath: String,
        originalPath: String,
        errorOutput: String,
        mutantsInFile: [MutantDescriptor],
        importStyle: ImportStyle
    ) throws -> [MutantDescriptor]

    static func regeneratedSchema(
        originalPath: String, keeping mutants: [MutantDescriptor], importStyle: ImportStyle = .implicit
    ) -> String?
}
```

Narrows a schematized SPM build that does not compile. `narrow` reads the sandbox files the compiler blamed (`<sandbox>/….swift:<line>:`), and for each one that maps back to a project file holding schematizable mutants — the mutants indexed by canonical path once per round, not resolved again for every blamed file — calls `excludeProblematicMutants`: from every error line it walks up to the nearest `case "<mutant id>":` — stopping at `default:` or `switch` — and takes those mutants out. `regeneratedSchema` rebuilds the file's schema from the original source with the mutants kept (reading each one's index with `MutantID.index(of:)`) and writes it over the sandbox copy. When no error line lands in a mutant's `case`, or the schema cannot be regenerated, the sandbox file goes back to a symlink to the original (`SandboxLink.restore`) and every mutant of the file is excluded. A link that cannot be restored throws `IntegrityError.sourceNotRestored`, and a narrowed schema that cannot be written throws its write error: both used to be ignored, leaving the broken schema in the sandbox to fail every later build. It then reports `.schemaNarrowed`, builds again and recurses with what it has excluded so far, until a build compiles or no new mutant is blamed — then it answers no artifact, and `MutantExecutor` falls back to `FallbackExecutor`.

---

## Execution/BaselineProbe.swift

```swift
struct BaselineProbe: Sendable {
    let configuration: RunnerConfiguration
    let launcher: any ProcessLaunching

    func probeTestBundles(in sandbox: Sandbox) async throws -> (bundles: [TestBundle], filter: String?)
}
```

Runs the unmutated suite on the SPM path before any mutant: each test bundle with each testing library, or `swift test --skip-build` (`ToolRequests.swiftTest`) when the build left no bundle. A library that reports no tests is dropped from the bundle; one that has tests must pass them, or the run ends with a `BaselineError` (the output goes to the logs directory when `--keep-logs` is set). Returns the probed bundles and the filter `TestTargetSelection` settled on; when no bundle reported any test, every bundle is kept with both libraries. See the probe under `TestExecutionStage` below for why it exists.

---

## Execution/ResultRecorder.swift

```swift
struct ResultRecorder: Sendable {
    let deps: ExecutionDeps
    let keepLogsPath: String?

    func cached(_ mutant: MutantDescriptor) async -> ExecutionResult?
    func record(
        _ mutant: MutantDescriptor,
        status: ExecutionStatus,
        duration: Double = 0,
        output: String = "",
        activated: Bool? = nil
    ) async -> ExecutionResult
    func finish(_ result: ExecutionResult) async
}
```

Where every verdict of a run goes, whichever path reached it. `record` writes the mutant's log (`MutantLogWriter`, when `--keep-logs` is set), resolves the killer test file for a kill, stores the verdict in the cache — which journals it, and the plan journal with it — then counts it and reports `.mutantFinished`. `cached` answers the cache's verdict through `CacheStore.cachedResult(for:)`, counted and reported as finished, or `nil`. `finish` only counts and reports.

`TestExecutionStage`, `FallbackExecutor`, `IncompatibleMutantExecutor` and `MutantExecutor` (for rerouted mutants that cannot be rewritten) all go through it; each used to repeat those steps, and not all of them. Since it, a fallback build failure and a mutant whose rewrite could not be applied leave a mutant log too — the fallback one carries the build error's description.

---

## Execution/ApplicationVerifier.swift

```swift
struct ApplicationVerifier: Sendable {
    var read: @Sendable (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }

    func verify(
        schematizedFiles: [SchematizedFile],
        mutants: [MutantDescriptor],
        sandbox: Sandbox,
        projectPath: String
    ) throws
}
```

Proves, before the build, that the sandbox holds what discovery produced. For each schematized file, the original must lie inside the project and the sandbox copy — at the original's path relative to the project — must exist, differ from the original, and contain `SupportDeclarations.perFile(for:)` its path; otherwise `schemaNotApplied` or `supportMissing`. Then every schematizable mutant must have `case "<id>":` in its file's copy, and every incompatible mutant must have `mutatedSourceContent` that differs from its original file; the ones that fail are thrown together as `mutantsNotApplied`, each as `<id> (<file>:<line>)`. `MutantExecutor` runs it on the whole input, and `FallbackExecutor` on each per-file sandbox. Each original is read, and each mutant path resolved, once per call however many mutants share the file. Every file is read through `read`, so a test can hand in the contents instead of writing them.

---

## Execution/IntegrityError.swift

```swift
enum IntegrityError: Error, Equatable, LocalizedError {
    case mutantsNotApplied(mutants: [String])
    case schemaNotApplied(path: String)
    case supportMissing(path: String)
    case activationNeverObserved(killed: Int)
    case sourceNotRestored(path: String)

    var errorDescription: String? { get }
}
```

Every case ends the run with exit code `1`. The descriptions name the mutants (the first ten, then a count) or the file, and say why the run stopped rather than reporting.

| Case | Thrown by |
|---|---|
| `mutantsNotApplied(mutants:)` | `ApplicationVerifier`: a schematizable mutant without its `case`, or an incompatible one whose content is missing or equals the original |
| `schemaNotApplied(path:)` | `ApplicationVerifier`: the sandbox copy is missing, unreadable, identical to the original, or the original lies outside the project |
| `supportMissing(path:)` | `ApplicationVerifier`: the copy lacks its `SupportDeclarations.perFile(for:)` block |
| `activationNeverObserved(killed:)` | `MutantExecutor.requireObservedActivation(in:)` |
| `sourceNotRestored(path:)` | `SandboxLink.restore(at:to:)`, from `IncompatibleMutantExecutor` and `SchemaNarrower` |

---

## Execution/ActivationMarker.swift

```swift
struct ActivationMarker: Sendable {
    static let environmentVariable: String  // "__SWIFT_MUTATION_TESTING_ACTIVATION_FILE"
    static let directoryName: String        // ".xmr-activation"

    let path: String

    init(for mutantID: String, in sandbox: Sandbox)
    func wasWritten() -> Bool
}
```

One marker per test run: `<sandbox>/.xmr-activation/<mutant id>-<UUID>`, created by the test process the first time the mutant's `case` runs, and read once by `wasWritten()`, which removes the file. `TestBundleInvocation.environment(mutantID:activationFile:)` puts the path in the test process's environment on the SPM path; `XCTestRunPlist.activating(_:activationFile:)` puts it in every test target's `EnvironmentVariables` on the Xcode path.

---

## Execution/ExecutionDeps.swift

```swift
struct ExecutionDeps: Sendable {
    let launcher: any ProcessLaunching
    let cacheStore: CacheStore
    let reporter: any ProgressReporter
    let counter: MutationCounter
    let killerTestFileResolver: KillerTestFileResolver
    var targetedSuites: [String: TargetedSuite] = [:]
}
```

Bundle of shared collaborators passed between `MutantExecutor` and the stage types. Avoids threading individual dependencies through every call site.

| Field | Description |
|---|---|
| `launcher` | Process runner used for every `swift`, `xcodebuild` and test bundle invocation |
| `cacheStore` | Shared actor for reading and writing result cache entries |
| `reporter` | Progress events sink (console or silent) |
| `counter` | Shared actor tracking the current mutant index |
| `killerTestFileResolver` | Maps killer test names to source file paths for granular cache invalidation |
| `targetedSuites` | The suites named after source files (`TargetedSuites.declared(in:read:)`), run first for a mutant of that file, on the SPM test pass and the incompatible SPM path |

---

## Execution/BaselineError.swift

```swift
enum BaselineError: Error, Equatable, LocalizedError {
    case testsFailed(tests: [String])
    case didNotFinish(seconds: Double)
    case runFailed(output: String)

    var errorDescription: String? { get }
}
```

Thrown when the unmutated project does not pass its own tests, which ends the run: every mutant would otherwise be reported killed by a failure that was already there.

| Case | Condition |
|---|---|
| `testsFailed(tests:)` | The probe ran the suite and named failing tests. The message lists them, and points out that tests run against a sandbox copy under the system temporary directory — a test deriving paths from `#filePath` can fail there while passing in place |
| `didNotFinish(seconds:)` | The probe hit `--timeout` |
| `runFailed(output:)` | The suite failed without naming a test — a crash, or a build problem the parser could not attribute |

---

## Execution/TestExecutionStage.swift

```swift
struct TestExecutionStage: Sendable {
    static let loadedTimeoutFactor: Double = 2
    static let retryWorkerShare = 4

    let deps: ExecutionDeps

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult]

    static func classify(_ status: ExecutionStatus, activated: Bool) -> ExecutionStatus
}
```

Runs each mutant's tests in parallel — `xcodebuild test-without-building` on the Xcode path (the artifact has a plist), the test bundles directly on the SPM one. The three passes below are three calls of one private `forEach(_:concurrency:run:collect:)`: a `withThrowingTaskGroup` that starts `concurrency` tasks and starts the next element as each finishes, and hands every outcome to `collect` on the calling task, so the results and the two retry lists are plain local arrays. `classify` turns a survivor whose activation marker was not written into `.noCoverage`; `IncompatibleMutantExecutor` classifies with it too.

A mutant whose run times out during that parallel pass is not recorded yet. Once the group has drained, every such mutant is run once more with at most a quarter of the workers (`retryWorkerShare`, never fewer than one), under the configured `--timeout`, and that second outcome is the one reported and cached. The parallel pass itself allows twice the configured timeout (`loadedTimeoutFactor`): a verdict that settles under load is the same verdict the mutant would get alone, so the wider limit only spares the second run, while a mutant that is still running at twice the limit is handed to the quieter pass, whose limit is the one the user asked for.

A mutant killed during the parallel pass without its activation marker is not recorded yet either. After the timeout pass, each such mutant runs once more, alone, one after another, under the configured `--timeout`, and that run's outcome is the one reported and cached. A flaky test usually passes the second time, and the mutant is then judged like any other run: survived, or `noCoverage` when its code still did not run. A kill that repeats without activation stays a kill, reported as an integrity warning. Kills that come from the timeout pass are not run a third time. Warnings are rare: over the campaign projects, 1 to 7 per run against 209 to 1275 mutants, under 1% of mutants, so the extra run costs little.

Measured on `swift-cpd` (944 tests), the suite takes 14s alone, 15s with 8 workers and 24s with 15 on a 12P+4E machine, so a 30s limit under 15 workers turned a third of all mutants into stragglers: each one cost its 30s in the parallel pass and was then run again in series, and the 26 mutants that time out for real cost the full limit twice. Doubling the loaded limit settles almost every straggler in the parallel pass, and a quarter of the workers is a load the machine does not notice (8 workers cost 8% over running alone) while it cuts the second pass by the same factor.

Before that pass, when the package was built to test bundles — one per test target — each bundle is run once with each testing library against the unmutated sandbox. That single run answers two questions at once. A library that reports no tests — exit 69 from SwiftPM's helper, or `Executed 0 tests` from `xctest` — is left out of every mutant's run: on a Swift Testing-only package that links swift-syntax, the `xctest` pass costs 13.8s just to load the bundle and find nothing, against 1.7s for the Swift Testing pass, and it used to run for every surviving mutant. And a library that does have tests must pass them: a failure, a crash or a timeout on the unmutated code ends the run with a `BaselineError` naming the tests, since nothing a mutant does afterwards could be attributed to the mutant. Before this the baseline was a separate `swift test --skip-build` of the whole suite followed by the probe — three runs of the suite to answer two questions. A bundle that reports no tests in either library is dropped from every mutant's run as well; the list that survives the probe, `[TestBundle]`, is fixed before the pass. When the package produced no bundle at all, `swift test --skip-build` is still the baseline, and both libraries are assumed present.

`--target` on this path names a test target: when a bundle carries that name, `TestTargetSelection` keeps only that bundle and passes no filter; when none does, every bundle runs with the name as the libraries' filter, as before. The probe runs the suite to the end; every mutant's run stops at its first failing test. See `ProcessRunner` in [09 — Reporting & Infrastructure](09-reporting-infrastructure.md) for how, and why it is safe.

**Targeted tests first.** On the SPM path a mutant in `Foo.swift` is first run against `FooTests` alone — `--filter FooTests` for Swift Testing, `-XCTest FooTests` for XCTest — and only if that does not kill it does the whole suite run. A kill in the targeted run is a kill in the full run, since the same test would fail there too, so the verdict is the full suite's by construction; everything else — survived, no tests matched, a timeout — falls through to the full run, which decides. `TargetedSuites.declared(in:read:)` reads the test files once, before the pass — the paths and contents of the run's `TestFilesHasher.Snapshot`, not a second listing or a second read — and keeps only the names whose file declares a type of that name (`struct FooTests`, `final class FooTests: XCTestCase`, …), so a file named after a convention the project does not follow costs nothing: without that check every mutant would pay the helper's start-up — 1.7s on `swift-cpd` — to run zero tests. Measured on `swift-cpd` from the `killedBy` of a full run, 62% of kills (479 of 772) come from the file's own suite.

The targeted run goes to the bundle of the test target that declares the suite, read from the test file's `Tests/<Target>/` directory. When that cannot be told — a test file outside `Tests/<Target>/` — every bundle gets the filter, and the ones without the suite report no tests and cost one process launch each. The full run goes through every bundle in name order and stops at the first failing test, whichever bundle it is in.

**One mutant on the Xcode path:**

```mermaid
flowchart TD
    M["MutantDescriptor"] --> CACHED{"cache hit?"}
    CACHED -- yes --> REPORT["report progress, return cached result"]
    CACHED -- no --> PLIST["ActivationMarker<br>XCTestRunPlist.activating(mutantID, activationFile:)"]
    PLIST --> ACQUIRE["pool.acquire SimulatorSlot"]
    ACQUIRE --> LAUNCH["xcodebuild test-without-building<br>-xctestrun -destination -resultBundlePath<br>-derivedDataPath -collect-test-diagnostics never<br>-only-testing when --target is set"]
    LAUNCH --> RELEASE["pool.release slot<br>marker.wasWritten"]
    RELEASE --> PARSE["ResultParser.parse"]
    PARSE --> CLEANUP["delete .xcresult"]
    CLEANUP --> STORE["ResultRecorder.record<br>log, cache, progress"]
    STORE --> REPORT2["return ExecutionResult"]
```

A fresh `.xctestrun` file is written for each mutant (UUID-named, next to the build's own, deleted after launch). The `.xcresult` bundle is deleted after `ResultParser` extracts failure details. A timeout or an unactivated kill is not recorded here but handed to the passes below.

---

**The three passes:**

```mermaid
flowchart TD
    MUTANTS["[MutantDescriptor]"] --> GROUP["forEach<br>concurrency workers<br>limit = --timeout × loadedTimeoutFactor"]
    GROUP -- settled --> RESULTS["[ExecutionResult]"]
    GROUP -- "timed out under load" --> STRAGGLERS["stragglers"]
    STRAGGLERS --> AGAIN["forEach, run again<br>concurrency ÷ retryWorkerShare workers<br>limit = --timeout"]
    AGAIN --> RESULTS
    GROUP -- "killed without activation" --> UNACTIVATED["unactivated kills"]
    UNACTIVATED --> ALONE["forEach, run again, alone<br>one worker<br>limit = --timeout"]
    ALONE --> RESULTS
```

**One mutant on the SPM path:**

```mermaid
flowchart TD
    M["MutantDescriptor"] --> CACHED{"cache hit?"}
    CACHED -- yes --> REPORT["report progress, cached result"]
    CACHED -- no --> SLOT["pool.acquire"]
    SLOT --> SUITE{"not reproducing, and a suite<br>named after the file?"}
    SUITE -- yes --> TARGETED["run that suite alone<br>bundles(declaring:)<br>stops at the first failure"]
    TARGETED -- killed --> PARSE["SPMResultParser"]
    TARGETED -- "survived, no tests, timed out" --> FULL["run the whole suite<br>every bundle, only the libraries the probe found<br>stops at the first failure"]
    SUITE -- no --> FULL
    FULL --> PARSE
    PARSE --> RELEASE["pool.release"]
    RELEASE --> STORE["ResultRecorder.record<br>log, cache, progress"]
    STORE --> REPORT2["ExecutionResult"]
```

## Execution/TestExecutionContext.swift

```swift
struct TestExecutionContext: Sendable {
    let artifact: BuildArtifact
    let sandbox: Sandbox
    let pool: SimulatorPool
    let configuration: RunnerConfiguration
    var bundles: [TestBundle] = []
    var testFilter: String?
    var targetedSuites: [String: TargetedSuite] = [:]

    func bundles(declaring suite: TargetedSuite) -> [TestBundle]
}
```

Bundles the execution-time dependencies required by `TestExecutionStage` and the fallback path.

| Field | Description |
|---|---|
| `artifact` | Build output containing the `.xctestrun` plist |
| `sandbox` | The sandbox directory hosting derived data and temporary files |
| `pool` | Simulator slot pool for acquiring/releasing parallel slots |
| `configuration` | Full runner configuration (timeout, concurrency, testTarget, etc.) |
| `bundles` | The test bundles a mutant's run invokes, each with the libraries the probe found tests in. Empty when the package produced no bundle, in which case `swift test --skip-build` runs instead |
| `testFilter` | The filter of the SPM full run, as `TestTargetSelection` left it — `nil` when `--target` named a bundle. The Xcode path reads `--target` from `configuration` instead, as `-only-testing` |
| `targetedSuites` | The test suites that exist and are named after a source file, by name, each with the test target that declares it, so a mutant in `Foo.swift` can run `FooTests` first |

`bundles(declaring:)` picks the bundle named after the suite's test target, and every bundle when the target is unknown or no bundle matches.

---

## Execution/TestLaunchResult.swift

```swift
struct TestLaunchResult: Sendable {
    let exitCode: Int32
    let output: String
    let xcresultPath: String
    let duration: Double
    var activated: Bool = false
}
```

Raw result from a single test run — `xcodebuild test-without-building`, or the bundle invocations of the SPM path.

| Field | Description |
|---|---|
| `exitCode` | Process exit code; `-1` means killed by timeout |
| `output` | Combined stdout + stderr |
| `xcresultPath` | Absolute path to the `.xcresult` bundle |
| `duration` | Wall-clock seconds from launch to termination |
| `activated` | Whether the mutant's `case` wrote its activation marker during this run (or, on the SPM path, during the targeted or the full run) |

---

## Execution/TestBundleInvocation.swift

```swift
struct TestBundleInvocation: Sendable {
    static let noTestsExitCode: Int32 = 69

    static func reportsNoTests(exitCode: Int32, output: String) -> Bool
    static func bundleURLs(in sandbox: Sandbox) -> [URL]

    let bundleURL: URL
    let framework: TestingFramework

    func requests(
        filter: String?,
        mutantID: String,
        workingDirectory: URL,
        timeout: Double,
        libraries: Set<TestingFramework> = [.xctest, .swiftTesting],
        stoppingAtFirstFailure: Bool = true,
        activationFile: String? = nil
    ) -> [ProcessRequest]

    static func environment(mutantID: String, activationFile: String?) -> [String: String]
}
```

Builds the process requests that run a package's test bundle directly, skipping `swift test`'s own build check. Two requests per mutant at most, ordered so the configured `--testing-framework` goes first:

| Library | Command |
|---|---|
| Swift Testing | `swiftpm-testing-helper --test-bundle-path <binary> <binary> --testing-library swift-testing [--filter <name>]` |
| XCTest | `xcrun xctest [-XCTest <name>] <bundle>` |

`environment(mutantID:activationFile:)` is what both requests, and the `swift test` fallback of `TestExecutionStage`, add to the inherited environment: `__SWIFT_MUTATION_TESTING_ACTIVE` carries the mutant id, and `ActivationMarker.environmentVariable` the marker path when there is one. The Swift Testing request adds `DYLD_FRAMEWORK_PATH` and `DYLD_LIBRARY_PATH`, pointing at the platform's frameworks so the helper can load the bundle; the two lists are joined with `Uniquing.keepingFirst`, so a key the mutant's environment already sets is not overwritten.

`bundleURLs(in:)` lists every `.xctest` under `.build/out/Products/Debug` in name order, one per test target; the order is what makes a run's output and its first failing test reproducible.

`reportsNoTests` recognises a library that has nothing to run — exit code 69 from SwiftPM's helper, or `Executed 0 tests` from `xctest` — which is what `BaselineProbe` uses to drop a library from every mutant's run. `stoppingAtFirstFailure` attaches `OutputStopRule.firstTestFailure` to each request; the probe passes `false`, because its job is to run the suite to the end.

**`DeveloperToolchain`** — resolves the active developer directory once per process:

```swift
enum DeveloperToolchain {
    nonisolated(unsafe) static var developerPath: String

    static func resolveDeveloperPath(
        running executable: URL = URL(fileURLWithPath: "/usr/bin/xcode-select"),
        arguments: [String] = ["-p"]
    ) -> String

    static var testingHelperPath: String { get }
    static var frameworksPath: String { get }
    static var librariesPath: String { get }
}
```

`resolveDeveloperPath` takes the executable to run so a test can point it at something that fails or prints bytes that are not text; both return `""`, and the paths built from it simply do not resolve.

---

## Execution/TestBundle.swift

```swift
struct TestBundle: Sendable, Equatable {
    static let allLibraries: Set<TestingFramework>

    let url: URL
    var libraries: Set<TestingFramework>
    var name: String { get }

    static func all(in sandbox: Sandbox) -> [TestBundle]
}
```

One built test bundle and the libraries a mutant's run invokes it with. `name` is the bundle's file name without `.xctest`, which is the test target's name; `TestTargetSelection` and `TestExecutionContext.bundles(declaring:)` match on it. `all(in:)` lists every bundle with both libraries. The fallback path, which does not probe, builds the same kind of list from the bundles `TestTargetSelection` keeps, each with `allLibraries`, and so does `BaselineProbe` when no bundle reported any test.

---

## Execution/TargetedSuite.swift

```swift
struct TargetedSuite: Sendable, Hashable {
    let name: String
    let testTarget: String?
}
```

One suite named after a source file, as `TargetedSuites.declared(in:read:)` found it.

| Field | Description |
|---|---|
| `name` | The test file's name without `.swift`, which is also the type it declares — `FooTests`. Passed as `--filter` to Swift Testing and `-XCTest` to XCTest |
| `testTarget` | The directory under `Tests/` that holds the file, the test target and so the bundle name; `nil` when the file is not laid out that way, and every bundle gets the filter |

---

## Execution/TargetedSuites.swift

```swift
enum TargetedSuites {
    static let suffix = "Tests"
    static let testsDirectory = "Tests"

    static func declared(
        in testFilePaths: [String],
        read: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> [String: TargetedSuite]
    static func suite(for sourcePath: String, among suites: [String: TargetedSuite]) -> TargetedSuite?
    static func testTarget(of testFilePath: String) -> String?
}
```

Answers "which test suite is named after this source file, if any, and which test target declares it". `declared(in:read:)` reads the project's test files once, before the test pass — `MutantExecutor` passes the run's `TestFilesHasher.Snapshot` contents as `read`, so not from disk again — and the result travels in `ExecutionDeps.targetedSuites` to both the test pass and the incompatible SPM path. Of the files whose name ends in `Tests`, it keeps the name of each one that *declares a type of its own name* — the text contains `struct FooTests`, `class FooTests` (so `final class FooTests: XCTestCase`), `actor FooTests` or `enum FooTests`. A file named `FooTests.swift` that declares `FooSpecs` does not count, and neither does a file that cannot be read as text. `testTarget(of:)` is the directory right under the last `Tests` component of the path — `CoreATests` for `Tests/CoreATests/FooTests.swift` — and `nil` for a test file that is not laid out that way.

That check is what makes the feature free for projects that do not follow the convention: `suite(for:among:)` — the suite keyed by the source file's name plus `Tests` — returns `nil`, no targeted run is attempted, and no mutant pays the test helper's start-up to run zero tests.

---

## Execution/TestTargetSelection.swift

```swift
struct TestTargetSelection: Sendable {
    let bundleURLs: [URL]
    let filter: String?

    static func make(target: String?, bundleURLs: [URL]) -> TestTargetSelection
}
```

What `--target` means on the SPM path. When a bundle's `TestBundle.name` equals the target, the selection is that bundle alone with no filter; otherwise — no target, or no bundle of that name — it is every bundle with the target, possibly `nil`, as the libraries' filter. `BaselineProbe` and `FallbackExecutor` both start from it, so the probe, the test pass and the fallback run the same tests.

---

## Execution/FallbackExecutor.swift

```swift
struct FallbackExecutor: Sendable {
    let deps: ExecutionDeps
    let configuration: RunnerConfiguration

    func execute(
        input: RunnerInput,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult]
}
```

When the baseline build for all schematized files fails (`BuildError.compilationFailed`), `MutantExecutor` delegates to `FallbackExecutor`. This executor rebuilds one schematized file at a time.

```mermaid
flowchart TD
    FILES["[SchematizedFile]"] --> LOOP["for each file with schematizable mutants"]
    LOOP --> CACHED{"every mutant of the file cached?"}
    CACHED -- yes --> FINISH["ResultRecorder.finish each"]
    CACHED -- no --> SF["SandboxFactory.create<br>single-file sandbox"]
    SF --> VERIFY["ApplicationVerifier.verify"]
    VERIFY --> BS["BuildStage"]
    BS -- success --> SEL["TestTargetSelection<br>every bundle with both libraries"]
    SEL --> TES["TestExecutionStage<br>test mutants in this file"]
    BS -- compilationFailed --> UNVIABLE["mark all mutants in file .unviable"]
    BS -- timedOut --> TIMEOUT["mark all mutants in file .timeout"]
    BS -- "any other error" --> THROW["rethrow: the run stops, nothing recorded"]
```

For each schematized file, creates a sandbox containing only that file's schematization (with a `SandboxFactory()` of its own), verifies it with `ApplicationVerifier`, builds it (Xcode or SPM), and runs the test suite against its mutants. A file whose mutants are all cached is not built: each cached verdict is reported through `ResultRecorder.finish`. The SPM test pass here runs without a baseline probe and without targeted suites: the bundles are those `TestTargetSelection` keeps, each with both libraries. The sandbox is released through `release(keepingFor:)` after each file. Only the two build errors that say something about the mutants become their verdict: `BuildError.compilationFailed` marks every mutant of the file `.unviable` and `BuildError.timedOut` marks them `.timeout`, each with a mutant log carrying the error's description. Every other error — a `CancellationError` from Ctrl-C, a launcher that could not start the build, `BuildError.xctestrunNotFound`, a failed read — is rethrown, so it ends the run instead of being recorded: verdicts reach the cache and the plan journal as soon as they are known, and a run resumed after an interruption would otherwise reuse `unviable` verdicts no build ever gave. Cached verdicts are read through `CacheStore.cachedResult(for:)` and every verdict is recorded through `ResultRecorder`.

---

## Execution/IncompatibleMutantExecutor.swift

```swift
struct IncompatibleMutantExecutor: Sendable {
    let deps: ExecutionDeps
    let sandboxFactory: SandboxFactory
    var importStyle: ImportStyle = .implicit

    static let outsideProjectMessage: String

    func execute(
        _ mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult]

    func record(_ verdict: Verdict, mutant: MutantDescriptor, configuration: RunnerConfiguration) async -> ExecutionResult
    func storeAndReport(
        mutant: MutantDescriptor,
        sandbox: Sandbox?,
        keepLogsPath: String?,
        buildOutput: String = "",
        status: ExecutionStatus = .unviable
    ) async -> ExecutionResult
    func buildStatus(exitCode: Int32) -> ExecutionStatus

    struct Verdict {
        let status: ExecutionStatus
        let output: String
        let duration: Double
        let activated: Bool?
        var buildFailed = false
        var isUnactivatedKill: Bool { get }
        init(raw: ExecutionStatus, output: String, duration: Double, marker: ActivationMarker?)
    }
}
```

Handles mutants that cannot be schematized, and the ones `SchemaNarrower` took out of the schema. `execute` answers every cached mutant first (`ResultRecorder.cached(_:)`), then hands the rest to the SPM path below or to `runXcode` (`IncompatibleMutantExecutor+Xcode.swift`). Both paths report a mutant without `mutatedSourceContent` unviable before any sandbox is touched, and, in a warm sandbox, a mutant whose file lies outside the project unviable with `outsideProjectMessage` before anything is written: the path would otherwise land on the sandbox root.

**Activation.** Both paths first build the copy `ActivationInstrumenter(importStyle:)` returns, and test it with an activation marker: the environment variable on the SPM path, the same name behind `TEST_RUNNER_` (`testRunnerPrefix`) on the Xcode path, since `xcodebuild` hands those to the test runner without the prefix. `Verdict` reads the marker and classifies the result like a schematized mutant's (`TestExecutionStage.classify`), and a kill without activation (`isUnactivatedKill`) is tested once more, without a rebuild, and judged by that run. When the instrumented copy fails to build, the plain `mutatedSourceContent` is built and tested instead, unmeasured (`activated == nil`): on the SPM path any failure but a timeout, on the Xcode path any build that fails (`buildFailed`). The same holds when the instrumenter returns `nil`. `MutantExecutor` passes the input's `importStyle`, so the import the instrumenter adds matches the project's. The activation is cached with the verdict.

`buildStatus(exitCode:)` makes a build that timed out `.timeout` and any other failed build `.unviable`; `storeAndReport` records such a verdict with the build output. Cache hits come from `ResultRecorder.cached(_:)`, and every verdict — including a mutation that could not be applied and a failed build — is recorded through `ResultRecorder.record`, by `record(_:mutant:configuration:)` or `storeAndReport`.

```mermaid
flowchart TD
    MUTANTS["incompatible and rerouted mutants"] --> CACHE{"ResultRecorder.cached?"}
    CACHE -- hit --> CACHED["cached result"]
    CACHE -- miss --> CONTENT{"mutatedSourceContent?"}
    CONTENT -- nil --> NA[".unviable: could not be applied"]
    CONTENT -- present --> PT{"project type"}
    PT -- ".xcode, reproducing" --> COLD["runXcodeCold<br>a sandbox and a cold build per attempt<br>xcodeWidth at a time"]
    PT -- ".xcode" --> XWARM["xcodeWidth XcodeWorkers<br>pool slot + createClean(disablingSwiftLint: true)<br>one cold build-for-testing each"]
    XWARM -- "none built" --> XUNVIABLE["every mutant unviable<br>with that build's output"]
    XWARM --> XDEAL["deal WarmMutants round-robin<br>over the workers that built"]
    XDEAL --> XWRITE["write instrumented copy over the link<br>incremental build-for-testing"]
    XWRITE -- built --> LAUNCH["test-without-building<br>-collect-test-diagnostics never"]
    XWRITE -- "build failed" --> XPLAIN["write plain copy<br>incremental build, test, unmeasured"]
    LAUNCH --> PARSE["TestResultResolver"]
    XPLAIN --> PARSE
    PARSE --> XRESTORE["SandboxLink.restore<br>remove .xcresult"]
    PT -- ".spm" --> WARM["warmSandboxes<br>concurrency ÷ 4 createClean sandboxes<br>swift build --build-tests in parallel"]
    WARM -- "none built" --> ALLUNVIABLE["every mutant unviable<br>with that build's output"]
    WARM --> DEAL["deal mutants round-robin<br>over the sandboxes that built"]
    DEAL --> WRITE["write instrumented copy<br>incremental swift build --build-tests"]
    WRITE -- built --> TESTS["targeted suite, then swift test<br>each stopped at the first failure"]
    WRITE -- "build failed, not a timeout" --> SPLAIN["write plain copy<br>rebuild, unmeasured"]
    SPLAIN --> TESTS
    TESTS --> SPMPARSE["SPMResultParser"]
    SPMPARSE --> SRESTORE["SandboxLink.restore"]
    XRESTORE --> STORE["ResultRecorder.record<br>results in input order"]
    SRESTORE --> STORE
    COLD --> STORE
```

**SPM path:** Uses warm sandboxes created via `SandboxFactory.createClean(projectPath:)`, each built once with `swift build --build-tests` (`ToolRequests.swiftBuildTests`) so that every mutant after the first costs an incremental rebuild rather than a cold one. For each mutant, writes the mutated source content directly into its sandbox — over the sandbox's symlink to the file, removing `.build/manifests` before each build — rebuilds, runs the tests, and restores the original file — the sandbox's symlink to it — through `SandboxLink.restore(at:to:)`. The tests run the way a schematized mutant's do: the file's own suite first (`TargetedSuites`, handed down by `MutantExecutor` as `targetedSuites`), then — when that kills nothing — `swift test` over the test target, each run stopped at its first failing test (`OutputStopRule.firstTestFailure`). A reproduction skips the targeted run and lets the whole suite finish. The incompatible path used to run the whole suite to its end for every mutant, killed or not. The restore used to be a `try?` in a `defer`: when re-linking failed, the file was simply gone from the sandbox and every later mutant of that worker failed to build and was cached `unviable`. A failed restore now throws `IntegrityError.sourceNotRestored` and ends the run. The warm sandboxes are released through `release(keepingFor:)` at the end, so a reproduction keeps them.

The number of sandboxes is a quarter of `--concurrency` (`TestExecutionStage.retryWorkerShare`, never fewer than one, never more than there are mutants), the same share the second test pass uses: a rebuild and a test run each spread over several cores, so four of them is a load the machine notices and eight is not worth it. Mutants are dealt round-robin over the sandboxes that built; a sandbox whose warm build failed is left out, and only when none built are the mutants reported unviable with that build's output. Results come back in input order whatever the completion order. Measured on `swift-cpd`, nine incompatible mutants took 118s of a 176s subset run when they ran one after another in a single sandbox — the first 26s for the cold build, then 9s each — which is what made this worth parallelising.

---

## Execution/IncompatibleMutantExecutor+Xcode.swift

```swift
extension IncompatibleMutantExecutor {
    static let testRunnerPrefix: String

    func runXcode(
        _ mutants: [MutantDescriptor],
        scheme: String,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult]

    func runXcodeCold(
        _ mutants: [MutantDescriptor],
        scheme: String,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult]

    static func xcodeWidth(concurrency: Int, poolSize: Int, mutantCount: Int) -> Int

    struct WarmMutant: Sendable {
        let index: Int
        let mutant: MutantDescriptor
        let content: String
    }

    struct XcodeWorker: Sendable {
        let sandbox: Sandbox
        let slot: SimulatorSlot
        let scheme: String
        let build: (exitCode: Int32, output: String)
    }
}
```

The Xcode path: warm sandboxes, as on the SPM path. `xcodeWidth(concurrency:poolSize:mutantCount:)` workers — a quarter of `--concurrency` (`TestExecutionStage.retryWorkerShare`), never more than the pool has slots nor than there are mutants, never fewer than one — are made in parallel: each `XcodeWorker` takes a pool slot for the whole pass, makes a clean sandbox with its SwiftLint phases off (`SandboxFactory.createClean(projectPath:disablingSwiftLint:)`) and runs one cold `build-for-testing` for that slot's destination. Each mutant with content becomes a `WarmMutant` carrying its input index. The mutants are dealt round-robin over the workers whose warm build passed; for each, the worker writes the instrumented copy over the sandbox's link to the file, rebuilds incrementally and runs `test-without-building` (with `-only-testing` when `--target` is set and `-parallel-testing-enabled NO`), and on a failed build writes the plain copy and builds again; then it puts the link back with `SandboxLink.restore` and removes the result bundles. When no warm build passes, every mutant is unviable with that build's output, as on SPM. Results come back in input order, by the `WarmMutant` index. Once the pass ends, or throws, every worker's sandbox is removed and its slot released; a worker that fails while warming releases its own slot, and the ones already warmed are released before the error is rethrown.

Restoring the link is what makes reuse correct, and it was checked before relying on it: Xcode's build system notices that the path now resolves to an older file and recompiles it, so the next mutant — in that file or another — does not run against the previous mutant's object. `XcodeWarmSandboxIntegrationTests` pins it on `CalcApp`: a killed mutant of `Calculator.swift`, then a mutant of `Validator.swift` that survives only if `Calculator.swift` is back to the original, then another killed one; without the restore the second is killed.

A reproduction keeps the earlier path (`runXcodeCold`): a sandbox of its own per attempt (`SandboxFactory.create(projectPath:mutatedFilePath:mutatedContent:)`), kept for inspection through `release(keepingFor:)`, with a cold build each — at most `xcodeWidth` mutants at a time, each taking a pool slot for its build and test.

**Measured.** On a benchmark copy of `CalcApp` — 300 generated source files added to the framework so that a build has something to do (a cold `build-for-testing` about 6 s on a 16-core machine, an incremental one after a one-file change about 2.8 s), Swift Testing tests, and 11 incompatible mutants in one file of `static let` initialisers, the other files excluded from mutation — each version ran three times end to end with `--operator-tier experimental --timeout 300 --no-cache`, every run reaching the same 7 killed, 2 survived and 2 no-coverage verdicts. "Phase" is the time from the first worker ready to the last verdict; medians of three:

| Destination | Version | Incompatible phase | Whole run |
|---|---|---|---|
| macOS (concurrency resolves to 1) | one cold sandbox per mutant, in turn | 129.3 s | 140.2 s |
| macOS | warm sandbox | 57.7 s (−55%) | 66.8 s (−52%) |
| iOS Simulator, `--concurrency 8` (2 workers) | one cold sandbox per mutant, in turn | 177.6 s | 229.7 s |
| iOS Simulator | cold sandboxes, 2 at a time | 105.0 s (−41%) | 128.1 s |
| iOS Simulator | warm sandboxes, 2 workers | 76.8 s (−57%) | 100.5 s (−56%) |

All three versions had `-collect-test-diagnostics never` for the comparison. `Scripts/xcode-incompatible-benchmark/benchmark.swift` makes the fixture (`fixture`), times a version (`run`), prints the table (`summarize`) and times the steps below with `xcodebuild` alone (`timings`); its header gives the worktree recipe for comparing versions and the patch an older one needs for the diagnostics flag. The fixture's cold build is short; on a project whose build takes minutes the cold build each mutant used to pay dominates even more, while the incremental rebuild grows only with the mutated file and what depends on it.

The build and the `test-without-building` run come from `ToolRequests` and share its derived data directory, `.xmr-derived-data` (this path used `.derived-data` before). Every `test-without-building`, here and in `TestExecutionStage`, passes `-collect-test-diagnostics never` (`ToolRequests.noTestDiagnostics`): by default `xcodebuild` collects a sysdiagnose-like report whenever a test fails, which the tool never reads. On the iOS Simulator that made each failing run take twice as long (20.7 s against 8.5 s on the benchmark fixture) and now and then hang — one in three in that measurement, with no other run alongside, and close to ten minutes before `xcodebuild` gave up in another — so that killed mutants came back as timeouts after the full limit. The flag predates every Xcode the tool can be built with — `swift-tools-version: 6.2` needs Xcode 26, and Apple documented `-collect-test-diagnostics never` on its developer forums in September 2022, in the Xcode 14 days — so it also holds when the tool drives an older Xcode chosen with `xcode-select`. It was checked on both test paths with Xcode 27: on the iOS Simulator every `test-without-building` of a schematized run (`-xctestrun`) and of an incompatible one carried it, with no timeout.

A failed build and a test run are both resolved through `TestResultResolver` (`ResultParser` for Xcode), each with a fresh `<UUID>.xcresult` path in the sandbox.

---

## Simulator/SimulatorPool.swift

```swift
actor SimulatorPool {
    init(baseUDID: String?, size: Int, destination: String, launcher: any ProcessLaunching)
    nonisolated let size: Int
    nonisolated var usesSimulators: Bool { get }
    func setUp() async throws
    func acquire() async throws -> SimulatorSlot
    func release(_ slot: SimulatorSlot) async
    func cancelPending(id: UUID)
    func tearDown() async
    static func orphanedClones(in listOutput: String, isAlive: (pid_t) -> Bool) -> [String]
}
```

Manages a fixed-size pool of simulator slots for parallel test execution.

| Destination | `setUp` behaviour | `tearDown` behaviour |
|---|---|---|
| `platform=macOS`, SPM, or another destination that needs no simulator | Creates `size` plain slots (empty UDID, the configured destination) | No-op |
| iOS / tvOS / watchOS Simulator | Sweeps orphaned clones, shuts the base simulator down, clones it `size` times in parallel (`CloneName.make`) and boots each clone; each slot's destination is the original `platform=` with `id=<clone>` | Shuts down and deletes each clone |

Each clone's UDID is recorded as soon as its `simctl clone` returns, and every clone call is waited for even after one fails. If any clone or boot fails, `setUp` runs `tearDown` before rethrowing, so a pool that fails part-way leaves no `XMR-<pid>-<session>-<n>` device behind — the caller only tears down a pool whose `setUp` succeeded.

**Clones left by other runs.** A run killed with `SIGKILL` or a crash never reaches `tearDown`, and its clones stay registered with CoreSimulator, booted ones still holding memory. Before cloning, `setUp` lists the devices and shuts down and deletes every one `orphanedClones(in:isAlive:)` names, called with `ProcessTree.isAlive`: a clone whose name carries the pid of a process that is gone (`CloneName.isOrphaned`), or one in the `XMR-<session>-<n>` form clones had before the pid was part of the name. The pid is what makes this safe: sweeping every `XMR-*` device would delete the simulators of another run in progress, the mistake the sandbox sweep once made (#86). A device list that cannot be read skips the sweep.

`usesSimulators` reports whether slots are simulator clones. On SPM the plain slots are what bound the parallel test runs to `--concurrency`. On an Xcode destination that needs no simulator every `xcodebuild` runs against the same machine, so `ConfigurationResolver.effectiveConcurrency` resolves concurrency down to 1 there, and `size` with it; it does the same under `--testing-framework xctest`.

`acquire()` returns an available slot immediately or suspends the caller until one is released. The suspension is wrapped with `withTaskCancellationHandler`: when the waiting task is cancelled, `cancelPending(id:)` removes its entry and resumes it with `CancellationError`, so a cancelled waiter neither hangs nor later swallows a released slot.

`release(_:)` resumes the oldest pending `acquire()` waiter, or returns the slot to the available pool if no waiters exist.

---

## Simulator/SimulatorPool+Make.swift

```swift
extension SimulatorPool {
    static func make(for configuration: RunnerConfiguration, launcher: any ProcessLaunching) async throws -> SimulatorPool
}
```

Builds the pool a run's destination needs: the Xcode destination, or `platform=macOS` for a package; plain slots (`baseUDID: nil`) when `SimulatorManager.requiresSimulatorPool(for:)` says no, otherwise clones of the base simulator `resolveBaseUDID(for:)` finds. `size` is the configured concurrency. The pool is not set up: `MutantExecutor` calls `setUp()` after the build.

---

## Simulator/CloneName.swift

```swift
enum CloneName {
    static let prefix: String   // "XMR-"
    static func make(session: String, index: Int, pid: pid_t = getpid()) -> String
    static func isOrphaned(_ name: String, isAlive: (pid_t) -> Bool) -> Bool
}
```

Names a simulator clone `XMR-<pid>-<session>-<index>`, the session being eight lowercase hex characters fixed per pool, and tells whether a device so named was left by a run that is gone. `isOrphaned` takes `isAlive` with no default, so every caller says how a pid is checked — `SimulatorPool` passes `ProcessTree.isAlive`, the tests a stub. A current-form name is orphaned when its positive pid is not alive; a pre-pid `XMR-<session>-<index>` name always is, since it has no owner to ask. A name that does not match either form is never orphaned, so a device the tool did not create is never touched.

---

## Simulator/SimulatorSlot.swift

```swift
struct SimulatorSlot: Sendable {
    let udid: String
    let destination: String
}
```

| Field | Description |
|---|---|
| `udid` | Clone UDID for simulator slots; `""` for a plain slot |
| `destination` | The destination string passed to `xcodebuild` for this slot |

---

## Simulator/SimulatorManager.swift

```swift
struct SimulatorManager: Sendable {
    init(launcher: any ProcessLaunching)
    static func requiresSimulatorPool(for destination: String) -> Bool
    func resolveBaseUDID(for destination: String) async throws -> String
    func waitForBooted(
        udid: String,
        maxAttempts: Int = 60,
        sleepDuration: Duration = .milliseconds(500)
    ) async throws
}
```

Provides simulator lifecycle utilities.

`requiresSimulatorPool(for:)` returns `false` when the destination contains `platform=macOS`; otherwise `true` when it contains `Simulator` or names no `platform=` at all, and `false` for any other platform, such as a device.

`resolveBaseUDID(for:)` takes `id=<udid>` from the destination string as it is; with only `name=<name>`, it looks the name up in `xcrun simctl list devices --json` and returns the first device of that name. Neither form, or a name no device has, throws `SimulatorError.deviceNotFound`.

`waitForBooted(udid:maxAttempts:sleepDuration:)` polls `xcrun simctl list devices --json` up to `maxAttempts` times, `sleepDuration` apart, until the simulator state is `Booted` — 30 seconds with the defaults — and throws `SimulatorError.bootTimeout` otherwise.

---

## Simulator/SimulatorError.swift

```swift
enum SimulatorError: Error, LocalizedError {
    case deviceNotFound(destination: String)
    case bootTimeout(udid: String)
    case cloneFailed(udid: String)

    var errorDescription: String? { get }
}
```

Conforms to `LocalizedError` to provide structured error descriptions that propagate through generic `catch` blocks.

| Case | Condition |
|---|---|
| `deviceNotFound` | No simulator matching the destination string |
| `bootTimeout` | Simulator did not reach `Booted` state within the polling window |
| `cloneFailed` | `xcrun simctl clone` returned a non-zero exit code; `udid` is the base simulator's |

---

## Execution/MutationCounter.swift

```swift
actor MutationCounter {
    init(total: Int)
    nonisolated let total: Int
    private(set) var completed: Int
    func increment() -> Int
}
```

Tracks execution progress across concurrent tasks. `total` is set once at construction and accessed without actor isolation. `increment()` returns the new index after incrementing (1-based), used to format `"<index>/<total>"` progress lines.

---

## Execution/RunnerInput.swift

```swift
struct RunnerInput: Sendable {
    let projectPath: String
    let projectType: ProjectType
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let schematizedFiles: [SchematizedFile]
    let mutants: [MutantDescriptor]
    var importStyle: ImportStyle = .implicit
}
```

The value produced by `DiscoveryPipeline` and consumed by `MutantExecutor`.

| Field | Description |
|---|---|
| `schematizedFiles` | One entry per source file containing schematizable mutations, each ending with its own support declarations |
| `mutants` | All mutants, sorted by global index; `isSchematizable` distinguishes the two populations |

### Execution/RunnerInput+Excluding.swift

```swift
extension RunnerInput {
    func excluding(_ ids: Set<String>) -> RunnerInput
}
```

The same input without the mutants of `ids`, for the fallback after `SchemaNarrower` gives up. A file left with no schematizable mutant is dropped. A file that keeps some gets its schema made again from the original source with `SchemaNarrower.regeneratedSchema` and only those mutants, so the excluded `case` that broke the build is not built again. When that schema cannot be made, the file keeps the schema it had. With no ids, the input comes back as it is.

---

## Execution/ExecutionResult.swift

```swift
struct ExecutionResult: Sendable, Codable {
    let descriptor: MutantDescriptor
    let status: ExecutionStatus
    let testDuration: Double
    let killerTestFile: String?
    let activated: Bool?
    let fromCache: Bool
}
```

| Field | Description |
|---|---|
| `descriptor` | The mutant that was tested |
| `status` | Outcome of the test run |
| `testDuration` | Wall-clock seconds for the test-without-building invocation; `0` for cache hits |
| `killerTestFile` | Source file path of the test that killed this mutant; `nil` for non-killed statuses and cache hits without metadata |
| `activated` | Whether the mutated code ran: `true`, `false`, or `nil` when it was not measured — a mutant the instrumenter could not reach or whose instrumented copy did not build, and unviable ones, which never ran |
| `fromCache` | `true` when the verdict was replayed from the cache rather than tested in this run; counted by the summaries' `Verdicts from cache` line |

---

## Execution/ExecutionStatus.swift

```swift
enum ExecutionStatus: Sendable, Equatable {
    case killed(by: String)
    case killedByCrash
    case survived
    case unviable
    case timeout
    case noCoverage

    var isKill: Bool { get }
}
```

`isKill` is `true` for `killed(by:)` and `killedByCrash`. `TestExecutionStage` and `IncompatibleMutantExecutor` use it to find a kill without activation, and `MutantExecutor.requireObservedActivation(in:)` to count the kills.

| Case | Condition |
|---|---|
| `killed(by:)` | Tests failed; `by` contains the test name or failure message |
| `killedByCrash` | Process crashed (fatal error, EXC_BAD_INSTRUCTION) |
| `survived` | Tests passed with the mutation active |
| `unviable` | Mutant could not be compiled |
| `timeout` | Test process was killed by the timeout handler (exit code `-1`) |
| `noCoverage` | No test exercised the mutated code |

Uses custom `Codable` encoding with `kind` / `by` keys to preserve the associated value of `killed(by:)` across cache serialisation.

---

← [Sandbox & Build](06-sandbox-build.md) | Next: [Result Parsing & Cache →](08-result-parsing-cache.md)
