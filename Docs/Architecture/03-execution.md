# Execution Pipeline

← [Discovery Pipeline](02-discovery.md) | Next: [Configuration →](04-configuration.md)

---

## Design

`MutantExecutor` is the entry point for the execution pipeline. It separates mutants into two populations — schematizable and incompatible — and routes each through the appropriate path. The executor supports both Xcode (`xcodebuild`) and SPM (`swift test`) project types via `ProjectType`.

```mermaid
flowchart TD
    IN[RunnerInput] --> PREP[prepareCacheStore\ngranular invalidation]
    PREP --> ALLCACHED{all cached?}
    ALLCACHED -- yes --> RETURN[return cached results]
    ALLCACHED -- no --> SF[SandboxFactory\ncreate sandbox]
    SF --> REG[SandboxCleaner.register]
    REG --> VERIFY[ApplicationVerifier\nevery mutant in the sandbox?]
    VERIFY -- no --> INTEGRITY[throw IntegrityError]
    VERIFY -- yes --> BS[BuildStage\nbuild-for-testing]
    BS -- compilationFailed --> RETRY[SchemaNarrower\nnarrow the schema, rebuild]
    RETRY -- gave up --> FBP[FallbackExecutor\none build per schematized file]
    BS -- success --> PROBE[BaselineProbe\neach test bundle and library once\nbaseline + which have tests]
    RETRY -- rebuilt --> PROBE
    PROBE -- fails --> ABORT[throw BaselineError]
    PROBE -- passes --> TES[TestExecutionStage\nthree passes, see below]
    TES --> TR[TestResultResolver]
    TR --> CLASSIFY[marker not written?\nsurvived → noCoverage]
    CLASSIFY --> CACHE[ResultRecorder\nlog · CacheStore · progress]
    FBP --> CACHE
    IN -- incompatible mutants --> IME[IncompatibleMutantExecutor\nwarm sandboxes, incremental rebuild per mutant]
    IME --> CACHE
    CACHE --> DEREG[SandboxCleaner.deregister\nsandbox.cleanup]
    DEREG --> SUM[RunnerSummary]
    SUM --> REPORTERS[TextReporter · ReportWriter\nJSON · HTML · Sonar · SARIF · Markdown]
```

## SandboxFactory

Creates an isolated copy of the project in `$TMPDIR/swift-mutation-testing/xmr-<pid>-<UUID>/` before every build. Supports both Xcode and SPM projects.

**Factory methods:**
- `create(projectPath:schematizedFiles:)` — full sandbox with schematized files (normal path)
- `createClean(projectPath:)` — clean sandbox without mutations (used by `IncompatibleMutantExecutor` for SPM shared sandbox)
- `create(projectPath:mutatedFilePath:mutatedContent:)` — sandbox with a single mutated file (incompatible mutants, Xcode path)

**Copy strategy:**
- Skips `.build`, `DerivedData`, and directories prefixed with `.xmr-`
- For `.xcodeproj`: creates fresh `xcuserdata`, copies `xcshareddata`, symlinks everything else
- For source files in `schematizedFiles`: writes the schematized content directly
- For all other files: creates symlinks to the originals (fast, space-efficient)
- Disables SwiftLint `PBXShellScriptBuildPhase` entries by patching the `project.pbxproj` of **every** `.xcodeproj` in the sandbox, at any depth — a workspace's projects included; `.build`, `DerivedData` and `Pods/` are not looked into
- Inserts `break` statements into empty `switch case` bodies to prevent compiler errors in schematized code

The original project is never touched. Cleanup removes the entire `xmr-*` directory when execution completes.

Right after the sandbox is created, and before anything is built, `ApplicationVerifier` checks that it holds every mutant: each schematized copy differs from its original and ends with the per-file support declarations, each schematizable mutant has its `case` in the copy, and each incompatible mutant has content that differs from the original. A mutant that did not make it ends the run with `IntegrityError` — a verdict on a mutation that is not in the build says nothing. See [Application Check](05-schematization.md#application-check).

## SandboxCleaner

Handles cleanup of orphaned sandbox directories and signal-based cleanup of the active sandbox.

**Orphaned cleanup (`removeOrphaned`):** Called through `SandboxCleaner.clearLeftovers()` by `RunCommand` just before `MutantExecutor` runs, and by `ReproduceCommand` — never on the `--version`, `--help` or `init` paths. Scans `$TMPDIR/swift-mutation-testing/` (or a provided directory) for directories prefixed with `xmr-` and removes the ones whose owning process is gone. This cleans up sandboxes from previous interrupted runs that were never cleaned up normally.

**Orphaned processes (`OrphanedProcessReaper`):** Runs right before the directory sweep. Lists the processes of the current user, reads each one's arguments (`sysctl(KERN_PROCARGS2)`), and kills — with its descendants — any process whose arguments point into an `xmr-<pid>-<UUID>` sandbox whose owner is gone. This is what cleans up after a run that could not clean up itself: killed with `SIGKILL`, or crashed, while a mutant was stuck in a loop. It works from the arguments rather than the directory because the sandbox may already have been deleted while the test binary kept running.

**Signal cleanup (`installSignalHandlers`):** Installs `SIGINT`, `SIGTERM` and `SIGHUP` handlers at startup. When a signal is received, the handler kills every test process group still in flight (`ProcessGroupRegistry`), removes the active sandbox directory (if registered) and calls `_exit(1)`. Test processes lead their own process groups, so without this a terminal's Ctrl-C would end the tool and leave a looping mutant running. The active path lives in `SandboxRegistry` as a C string behind an `Atomic` — C signal handlers cannot capture Swift context, and a single atomic exchange per operation means no path is ever freed twice.

**Lifecycle:** `MutantExecutor` calls `register(sandbox)` after creating the sandbox and `deregister()` after cleanup (both on the success and error paths). This ensures the signal handler always has the correct path.

## BuildStage

Runs a single build for all schematizable mutants.

**Xcode path:** `xcodebuild build-for-testing` → find `.xctestrun` → parse plist → `BuildArtifact`

**SPM path:** `swift build --build-tests` → `BuildArtifact` (no `.xctestrun` needed)

```mermaid
flowchart TD
    A{ProjectType?}
    A -- .xcode --> B[xcodebuild build-for-testing\n-scheme -destination\n-derivedDataPath\n-workspace or -project]
    A -- .spm --> C[swift build --build-tests]
    B --> D{Exit code?}
    C --> D
    D -- 0 --> E[BuildArtifact]
    D -- non-zero --> F[throw BuildError.compilationFailed]
```

| | |
|---|---|
| Input | `Sandbox`, project type, the resolved `XcodeContainer`, timeout |
| Output | `BuildArtifact` — derived data path + `.xctestrun` URL (Xcode) or sandbox path (SPM) |

The container's relative path is passed as `-workspace` or `-project`, from the sandbox root. The same arguments go to the per-mutant `xcodebuild` calls of `IncompatibleMutantExecutor`, which used to pass none and so built whatever `xcodebuild` found on its own.

**`ToolRequests`** builds every `swift` and `xcodebuild` request of a run — `swift build --build-tests`, `swift test --skip-build [--filter]`, `xcodebuild build-for-testing` and the other `xcodebuild` calls — so the schematized, fallback, incompatible and baseline paths build and test a sandbox the same way, with one derived data directory, `<sandbox>/.xmr-derived-data`. The incompatible Xcode path used `.derived-data` before.

`BuildError` conforms to `LocalizedError`, providing structured error descriptions. On `BuildError.compilationFailed`, `MutantExecutor` hands an SPM build to `SchemaNarrower`, which takes out the mutants whose `case` the compiler blamed, regenerates their files' schemas and rebuilds until the build compiles; when it gives up — and always on the Xcode path — `FallbackExecutor` takes over with per-file rebuilds rather than aborting. Any other thrown error propagates up.

## SimulatorPool

`SimulatorPool` is an `actor` that manages a pool of simulator slots for parallel test execution. `SimulatorPool.make(for:launcher:)` picks the pool from the configuration's destination: simulator clones when `SimulatorManager.requiresSimulatorPool(for:)` says so, plain slots otherwise.

| Destination | Behaviour |
|---|---|
| `platform=macOS` and SPM | Single slot, no simulator needed; `setUp` and `tearDown` are no-ops |
| iOS / tvOS / watchOS | Clones the base simulator N times (one per concurrency slot); boots each clone on `setUp`; shuts down and deletes on `tearDown` |

**The pool is what bounds parallelism.** A run with no simulators to clone gets one slot, so every worker beyond the first waits in `acquire()` — `--concurrency` buys nothing there. `ConfigurationResolver.effectiveConcurrency` resolves the figure down to 1 for those runs rather than reporting a number the pool will not honour, and `usesSimulators` lets the reporter say "worker" instead of claiming simulators that do not exist.

`acquire()` returns an available `SimulatorSlot` or suspends the caller until one is released. A `withTaskCancellationHandler` wraps the suspension — if the owning task is cancelled, the slot is released immediately to avoid a permanent deadlock.

`SimulatorError` conforms to `LocalizedError` and covers three failure modes: `deviceNotFound(destination:)`, `bootTimeout(udid:)`, and `cloneFailed(udid:)`. Each provides a structured `errorDescription` for diagnostics.

## Baseline Validation (SPM)

Before the first mutant runs, the suite is run once with no mutant selected. `__swiftMutationTestingID_<hash>` is empty, so every schema falls through to its `default` branch and the original code executes.

The run continues only if that suite passes. A suite that already fails without a mutation kills every mutant it reaches, so every verdict it produces is worthless — and nothing in the report would reveal it. `BaselineProbe` throws `BaselineError` instead, naming the failing tests, the timeout that stopped the suite, or the output it failed with.

**The baseline and the library probe are the same run.** A package builds one test bundle per test target. Each bundle is invoked once with each testing library against the unmutated sandbox, and that single invocation answers both questions: a bundle and library reporting no tests — exit 69 from SwiftPM's helper, `Executed 0 tests` from `xctest` — is dropped from every mutant's run, and one that does have tests must pass them. A bundle with tests in neither library is dropped altogether. Only when no bundle was produced does the baseline fall back to a separate `swift test --skip-build`. The probe runs the suite to the end; mutants stop at their first failing test.

The Xcode path does not validate a baseline yet and has the same exposure.

## TestExecutionStage

Runs each mutant's tests in parallel via `withThrowingTaskGroup` — `xcodebuild test-without-building` on the Xcode path, the test bundle directly on the SPM one — in three passes.

```mermaid
flowchart TD
    MUTANTS["[MutantDescriptor]"] --> TG
    subgraph TG["pass 1 — withThrowingTaskGroup (concurrency N, limit = timeout × 2)"]
        T1["Task: mutant 1\nacquire slot → targeted suite → full suite → release"] & T2["Task: mutant 2"] & T3["Task: mutant N"]
    end
    TG -- settled --> RESULTS["[ExecutionResult]"]
    TG -- still running at the limit --> SG
    subgraph SG["pass 2 — the stragglers (concurrency ÷ 4, limit = timeout)"]
        S1["Task: straggler 1"] & S2["Task: straggler M"]
    end
    SG --> RESULTS
    TG -- killed without activation --> RG
    subgraph RG["pass 3 — kills without activation (one at a time, limit = timeout)"]
        R1["Task: unactivated kill 1"] --> R2["Task: unactivated kill K"]
    end
    RG --> RESULTS
```

**Per-mutant execution, Xcode path:**

1. Check cache — return cached result immediately if `noCache` is false and a match exists (`ResultRecorder.cached`, which reads `CacheStore.cachedResult(for:)`)
2. Activate the mutant: `XCTestRunPlist.activating(_:)` injects the mutant ID into `EnvironmentVariables.__SWIFT_MUTATION_TESTING_ACTIVE` in a fresh `.xctestrun` copy
3. Acquire a simulator slot from the pool
4. Run `xcodebuild test-without-building -xctestrun <path> -resultBundlePath <xcresult>`
5. Release the simulator slot
6. Parse the result via `ResultParser`
7. Record the verdict through `ResultRecorder`: mutant log, `CacheStore`, progress

**Per-mutant execution, SPM path:** the mutant id travels in the environment rather than in a plist, and the bundle is invoked directly instead of through `swift test`. Two things happen before the whole suite is asked:

1. If a suite is named after the mutated file — `FooTests` for `Foo.swift`, and it declares a type of that name — it runs alone first, in the bundle of the test target that declares it. A failure there settles the verdict, and the rest of the suite is not run.
2. Otherwise, or if that run let the mutant live, the whole suite runs: every bundle in name order, each with only the libraries the probe found tests in, stopping at the first failing test.

Either run stops at its first failing test: a mutant is killed by one test, and `TestOutputParser` reports that one. See `ProcessRunner` in [09 — Reporting & Infrastructure](../CodeBase/09-reporting-infrastructure.md) for the mechanism.

Both paths hand each test process an activation marker path. A passing suite whose marker was never written is reported as `noCoverage` rather than `survived`; a kill without the marker is run once more, and a kill or a timeout without the marker in the final run keeps its verdict and becomes an integrity warning. See [Activation Marker](05-schematization.md#activation-marker).

**Three passes.** The first runs every mutant with `concurrency` workers and a limit of twice `--timeout`; a mutant still running at that point is not recorded, it is set aside. Once the group drains, the stragglers run again with a quarter of the workers and the configured `--timeout`, and that second outcome is the one reported. A verdict that settles under load is the verdict the mutant gets alone, so the wider limit only spares the second run — and the second pass has no contention to blame for a timeout.

**Rerun of kills without activation.** A mutant killed in the first pass without its marker is set aside too. After the timeout pass, each one runs once more, alone, under the configured `--timeout`, and that run decides. A flaky test usually passes the second time; a kill that repeats without activation is systematic and stays an integrity warning.

**Dynamic concurrency:** each pass seeds its workers, then adds one new task for each completed task, keeping exactly that many active at all times.

## FallbackExecutor

When the baseline build for all schematized files fails (`BuildError.compilationFailed`), `MutantExecutor` delegates to `FallbackExecutor`. This executor rebuilds one schematized file at a time — if one file causes a compilation error, the others can still be tested.

```mermaid
flowchart TD
    FILES["[SchematizedFile]"] --> LOOP["For each file"]
    LOOP --> SF[SandboxFactory\nsingle-file sandbox]
    SF --> BS[BuildStage]
    BS -- success --> TES[TestExecutionStage\ntest mutants in this file]
    BS -- failed --> UNVIABLE[Mark all mutants in file as .unviable]
```

For each schematized file, `FallbackExecutor` creates a sandbox containing only that file's schematization, builds it, and runs the test suite against its mutants. Files whose builds fail to compile have all their mutants marked as `.unviable` (`.timeout` when the build timed out), each with a mutant log holding the build error; any other error — cancellation included — is rethrown and recorded as no verdict, since the journal would carry it into a resumed run. Verdicts are recorded through `ResultRecorder`.

## IncompatibleMutantExecutor

Handles mutants that cannot be schematized — mutations outside function bodies (e.g. in stored property initializers or global scope). Each incompatible mutant requires its own rebuild before its tests can run, which makes these the most expensive mutants in a run.

```mermaid
flowchart TD
    MUTANT[MutantDescriptor\nisSchematizable = false] --> PT{ProjectType?}
    PT -- .xcode --> SF2[SandboxFactory\ncreate mutant-only sandbox]
    SF2 --> BS2[BuildStage\nbuild-for-testing]
    BS2 -- success --> TE2[xcodebuild test-without-building]
    BS2 -- compilationFailed --> UNVIABLE[.unviable]
    TE2 --> RP2[TestResultResolver]
    PT -- .spm --> WARM[warmSandboxes\nconcurrency ÷ 4, built in parallel]
    WARM -- none built --> UNVIABLE
    WARM --> DEAL[mutants dealt round-robin\nover the sandboxes that built]
    DEAL --> WRITE[write mutated file\nincremental rebuild → tests → restore]
    WRITE --> SPM[SPMResultParser]
```

Cache hits and every verdict — a mutation that could not be applied and a failed build included — go through `ResultRecorder`, as on the other paths.

**Activation:** each mutant is first built with a call that records when its mutated code runs, and tested with the activation marker, so an unreached survivor is `noCoverage` and a kill without activation is run once more, as on the schematized path. If that copy does not build, the plain mutant is built and tested unmeasured. See [Activation Marker](05-schematization.md#activation-marker).

**Xcode path:** Each incompatible mutant creates its own sandbox via `SandboxFactory.create(projectPath:mutatedFilePath:mutatedContent:)`, which applies the single mutation directly without schematization. Runs sequentially, each with a full build + test cycle.

**SPM path:** Uses warm sandboxes created via `SandboxFactory.createClean(projectPath:)` — a quarter of `--concurrency` of them, never fewer than one and never more than there are mutants — each built once up front so that every mutant after the first costs an incremental rebuild rather than a cold one. Mutants are dealt round-robin over the sandboxes that built; for each, the mutated source is written into its sandbox, the package is rebuilt and tested, and the original file restored. A sandbox whose warm build failed is left out, and only when none built are the mutants reported unviable with that build's output.

## TestResultResolver

`TestResultResolver` determines the `TestRunOutcome` of a completed test run. It delegates to the appropriate parser based on project type.

```mermaid
flowchart TD
    TLR[TestLaunchResult] --> TR[TestResultResolver]
    TR -- .xcode --> RP[ResultParser\nxcresulttool + output parsing]
    TR -- .spm --> SP[SPMResultParser\noutput-only parsing]
    RP --> OUT[TestRunOutcome]
    SP --> OUT
```

**Xcode path (`ResultParser`):** Inspects stdout/stderr for XCTest and Swift Testing failure patterns, then parses the `.xcresult` bundle via `xcresulttool` for detailed failure information. The `.xcresult` bundle is deleted after parsing.

**SPM path (`SPMResultParser`):** Parses exit code and stdout/stderr output only (no `.xcresult` bundles). Uses `TestOutputParser` to detect failure patterns.

| Condition | Outcome |
|---|---|
| Exit code `-1` (killed by timeout) | `.timedOut` |
| Exit code `0` | `.testsSucceeded` (survived) |
| Exit code non-zero + test failure pattern | `.testsFailed(failingTest:)` (killed) |
| Exit code non-zero + empty output | `.crashed` |
| Exit code non-zero + no parseable failure | `.unviable` |

**Failure patterns detected:**

| Framework | Pattern |
|---|---|
| XCTest | `Test Case '-[…]' failed` |
| Swift Testing | `Test "…" failed`, `Issue recorded` |

## CacheStore

`CacheStore` is an `actor` that persists `ExecutionStatus` results across runs, keyed by a SHA256-derived `MutantCacheKey`. It supports granular per-file cache invalidation.

```
MutantCacheKey
├── fileContentHash    — SHA256 of the source file content
├── operatorIdentifier — mutation operator name
├── utf8Offset         — mutation position
├── originalText       — token before mutation
└── mutatedText        — token after mutation
```

Cache is stored at `<project>/.swift-mutation-testing-cache/results.json`. A cached result is used only if `noCache` is false.

**Granular invalidation:** Instead of invalidating the entire cache when any test file changes, `CacheStore` tracks which test file killed each mutant via `killerTestFile` metadata. On each run, `MutantExecutor.prepareCacheStore` computes per-file test hashes via `TestFilesHasher.snapshot`'s `hashes`, compares them against stored hashes via `changedTestFiles(current:)` to produce a `TestFileDiff`, and calls `invalidate(diff:)` with status-aware rules:

| Change | `.killed` | `.survived` / `.noCoverage` / `.timeout` / `.killedByCrash` | `.unviable` |
|---|---|---|---|
| Test file **added** | kept | invalidated | kept (permanent) |
| Test file **modified** | invalidated if killer matches | invalidated | kept (permanent) |
| Test file **removed** | invalidated if killer matches | invalidated | kept (permanent) |

`.unviable` is permanent because it is a property of the mutant: a mutant that does not compile stays uncompilable however the tests change. Everything else is a statement about what happened when the tests ran, and is re-measured — including `.killedByCrash`, which used to be grouped with `.unviable` and so could never be cleared once recorded.

Each entry also remembers whether the mutated code ran, so a cached `noCoverage` stays `noCoverage` and a cached kill without activation is still reported as a warning. The format is versioned (`formatVersion` 3: 2 added activation, 3 measured it for incompatible mutants); a cache in an older format is discarded once, with a warning.

**Test selection:** the metadata also records what the tests ran against — the Xcode scheme, destination and container, `--target` and the testing library (`CacheTestSelection`). When a run's selection differs from the cache's, every cached verdict and the journal are discarded first, with a note on stderr: a verdict from one test target says nothing about another. The console and Markdown summaries show `Verdicts from cache: N of M` whenever some verdicts were reused, so a reused verdict is never invisible.

Source changes are handled separately, by the key rather than by the diff: `MutantCacheKey.fileContentHash` is the hash of the unmutated file, so editing the code under test produces different keys and the old verdicts are simply not found.

`KillerTestFileResolver` maps test names back to source file paths by matching XCTest class names and Swift Testing function names against the project's test file list.

## ResultRecorder

Every verdict, whichever path reached it, goes through `ResultRecorder.record(...)`: the mutant's log (`MutantLogWriter`, under `--keep-logs`), the cache and its journal — and the plan journal of a planned run — the killer test file, the progress count and the `mutantFinished` event. A cached verdict comes back through `cached(_:)`, counted and reported the same way. Before it, each executor repeated those steps and some skipped the log: a fallback build failure or a mutation that could not be applied now leaves a mutant log like any other verdict.

## Reporting

### Progress Reporting

`ConsoleProgressReporter` (actor) streams build events and per-mutant results to stdout during execution. `SilentProgressReporter` is a no-op substitute used when `--quiet` is active.

### Final Reports

`RunnerSummary` aggregates all `ExecutionResult` values and computes the mutation score.

**Score formula:**

```
detected   = killed + killedByCrash + timedOut
undetected = survived + noCoverage
score      = detected / (detected + undetected) × 100
```

| Reporter | Format | Activated by |
|---|---|---|
| `TextReporter` | Human-readable console summary | Always |
| `JsonReporter` | Stryker JSON schema | `--output <path>` |
| `HtmlReporter` | Interactive HTML dashboard | `--html-output <path>` |
| `SonarReporter` | SonarQube generic issue import format | `--sonar-output <path>` |
| `SarifReporter` | SARIF 2.1.0, for GitHub code scanning | `--sarif-output <path>` |
| `MarkdownReporter` | Markdown summary, with the quality gate | `--markdown-output <path>` |

`ReportWriter` writes every requested report file from one table — label, path, writer — and warns through `StandardError` when one cannot be written.

## Concurrency Model

| Component | Model |
|---|---|
| `SimulatorPool` | `actor` — manages slot availability and pending acquire requests |
| `CacheStore` | `actor` — serialises reads and writes to the result cache |
| `MutationCounter` | `actor` — tracks the current progress index |
| `ConsoleProgressReporter` | `actor` — serialises output to stdout |
| `TestExecutionStage` | `withThrowingTaskGroup` — N tasks, dynamically refilled |
| `ProcessRunner` | `withTaskCancellationHandler` + `withCheckedThrowingContinuation` — kills process on cancel |
| `SPMProcessLauncher` | `ProcessLaunching` conformance backed by `ProcessRunner`; on timeout it kills the process group and the descendants `ProcessTree` snapshotted before the first signal |
| `SandboxRegistry` | `Atomic` holding a C string for signal handler access; each operation takes the pointer out with one `exchange` |
| `ProcessGroupRegistry` | Fixed array of `Atomic<pid_t>` slots holding the test process groups in flight; the signal handler kills them with no lock taken |
| All data types | `Sendable` value types — safe to cross actor boundaries |

---

← [Discovery Pipeline](02-discovery.md) | Next: [Configuration →](04-configuration.md)
