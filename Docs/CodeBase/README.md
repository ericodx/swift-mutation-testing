# CodeBase Reference

Type-level reference for every public and internal type in `swift-mutation-testing`. Each document covers one module or cohesive group of types.

---

## Index

| Document | Coverage |
|---|---|
| [01 — Entry Point](01-entry-point.md) | the executable's `main.swift`, `SwiftMutationTesting`, `Command` and its seven commands (`HelpCommand`, `VersionCommand`, `InitCommand`, `PlanCommand`, `MergeCommand`, `ReproduceCommand`, `RunCommand`), `RunConclusion`, `CommandSupport`, `ExitCode`, `HelpText`, `Version`, `UsageError` |
| [02 — Configuration](02-configuration.md) | `CommandLineParser`, `ParsedArguments`, `RunnerConfiguration`, `BuildOptions`, `ReportingOptions`, `FilterOptions`, `ProjectType`, `XcodeContainer`, `XcodeContainerLocator`, `TestingFramework`, `ConfigurationResolver`, `ConfigurationFileParser`, `ConfigurationFileWriter`, `ProjectDetector`, `DetectedProject`, `GateOptions` |
| [03 — Discovery Pipeline](03-discovery-pipeline.md) | `DiscoveryPipeline`, `OperatorRegistry`, `OperatorTier`, `DiscoveryInput`, `FileDiscoveryStage`, `ExcludePattern`, `FileDiscoveryError`, `ParsingStage`, `MutantDiscoveryStage`, `MutantIndexingStage`, `SchematizationStage`, `IncompatibleRewritingStage`, `SourceFile`, `ParsedSource`, `MutationPoint`, `IndexedMutationPoint`, `MutantDescriptor`, `MutantID`, `MutationExclusion`, `DeclarationPath`, `MutantFingerprint` |
| [04 — Mutation Operators](04-mutation-operators.md) | `MutationOperator`, `OperatorVisitor`, `VisitorOperator`, `MutationSyntaxVisitor`, `ReplacementKind`, all 7 operator typealiases and visitors, `SuppressionAnnotationExtractor`, `SuppressionFilter`, `SuppressionVisitor`, `InfiniteLoopBodyVisitor`, `InfiniteLoopBodyExtractor`, `InfiniteLoopFilter`, `HostBuildConfiguration`, `InactiveRegionExtractor`, `InactiveRegionFilter` |
| [05 — Schematization](05-schematization.md) | `SchemataGenerator`, `SchemaGeneration`, `SupportDeclarations`, `ActivationInstrumenter`, `ImportStyle`, `FunctionBodyShape`, `MutationRewriter`, `UTF8Splice`, `TypeScopeVisitor`, `FunctionBodyScopes`, `FunctionBodyScope`, `SchematizedFile` |
| [06 — Sandbox & Build](06-sandbox-build.md) | `SandboxFactory`, `SandboxLink`, `SandboxName`, `SandboxCleaner`, `OrphanedProcessReaper`, `SandboxRegistry`, `Sandbox`, `BuildStage`, `ToolRequests`, `BuildArtifact`, `BuildError` |
| [07 — Execution](07-execution.md) | `MutantExecutor`, `SchemaNarrower`, `BaselineProbe`, `ResultRecorder`, `ExecutionDeps`, `ApplicationVerifier`, `IntegrityError`, `ActivationMarker`, `TestExecutionStage`, `TestExecutionContext`, `TestBundle`, `TestTargetSelection`, `TargetedSuite`, `TestLaunchResult`, `TestBundleInvocation`, `DeveloperToolchain`, `TargetedSuites`, `FallbackExecutor`, `IncompatibleMutantExecutor`, `SimulatorPool`, `CloneName`, `SimulatorSlot`, `SimulatorManager`, `SimulatorError`, `MutationCounter`, `RunnerInput`, `ExecutionResult`, `ExecutionStatus`, `BaselineError` |
| [08 — Result Parsing & Cache](08-result-parsing-cache.md) | `TestResultResolver`, `ResultParser`, `TestRunOutcome`, `TestOutputParser`, `SPMResultParser`, `XCResultParser`, `CacheTestSelection`, `CacheStore`, `CacheMetadata`, `MutantCacheKey`, `TestFileDiff`, `KillerTestFileResolver` |
| [09 — Reporting & Infrastructure](09-reporting-infrastructure.md) | `ProgressReporter`, `ConsoleProgressReporter`, `SilentProgressReporter`, `RunnerEvent`, `RunnerSummary`, `ExecutionResult+ReportStatusReason`, `RunnerSummary+DetectionLine`, `RunnerSummary+Cache`, `TextReporter`, `JsonReporter`, `HtmlReporter`, `String+HtmlEscaped`, `SonarReporter`, `SarifReporter`, all `Sarif*` types and `SarifRuleCatalog`, `MarkdownReporter`, `GateResult+Summary`, `ReportFormat`, `ReportWriter`, `ExecutionStatus+MutationReportStatus`, `ExecutionStatus+ProgressIcon`, all `MutationReport*` types (with `MutationReportConfig`), all `Sonar*` types, `MutantLogWriter`, `ProcessLaunching`, `RunnerLaunching`, `ProcessRequest`, `ProcessRunner`, `SPMProcessLauncher`, `XcodeProcessLauncher`, `SleepInhibitor`, `StandardOutput`, `StandardError`, `FileSystem`, `VersionedJSON`, `JSONLines`, `OnceWarning`, `OutputStopRule`, `OutputWatcher`, `SystemCalls`, `CanonicalPath`, `ProcessTree`, `ProcessArguments`, `TimeoutEscalation`, `ProcessGroupRegistry`, `XCTestRunPlist`, `ProjectRelativePath`, `TestFilesHasher`, `Uniquing` |
| [10 — Quality Gate](10-quality-gate.md) | `GatePolicy`, `QualityGate`, `GateResult`, `Baseline`, `BaselineScope`, `BaselineEntry`, `BaselineStore`, `GateError`, `GateReporter` |
| [11 — Plans](11-plans.md) | `Plan`, `PlanStore`, `PlanError`, `Planner`, `PlanMaterializer`, `Shard`, `ShardSelector`, `PlanJournal`, `PlanResumer`, `RunIdentity`, `RunnerConfiguration+Plan`, `ResultMerger`, `MergeError`, `Reproducer`, `Reproduction` |

---

## Quick Reference

### Value flow between pipelines

```
DiscoveryInput
  → FileDiscoveryStage        → [SourceFile]            ┐
  → ParsingStage              → [ParsedSource]          │ Planner
  → MutantDiscoveryStage      → [MutationPoint]         │
  → MutantIndexingStage       → [IndexedMutationPoint]  ┘ → Plan (+ plan.json through PlanStore)
  → SchematizationStage       → [SchematizedFile], [MutantDescriptor]  ┐ PlanMaterializer
  → IncompatibleRewritingStage → [MutantDescriptor]                     ┘
  → RunnerInput

RunnerInput
  → SandboxFactory → Sandbox
  → BuildStage     → BuildArtifact
  → TestExecutionStage → TestResultResolver → [ExecutionResult]
  → FallbackExecutor (on build failure)     → [ExecutionResult]
  → IncompatibleMutantExecutor              → [ExecutionResult]
  → RunnerSummary
  → RunConclusion → TextReporter, QualityGate, ReportWriter → Reporters, GateReporter
```

### Actors

| Actor | Responsibility |
|---|---|
| `SimulatorPool` | Manages simulator slot availability |
| `CacheStore` | Serialises reads/writes to result cache |
| `MutationCounter` | Tracks progress index across concurrent tasks |
| `ConsoleProgressReporter` | Serialises progress output to stdout |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Error (usage, build failure, unexpected) |
| `2` | Quality gate failed (`ExitCode.gateFailed`) |

### Regions the suite deliberately does not cover

Region coverage is **99.84% — six regions of 3711 missed**. The regions left are listed here with the reason, so that the next person measuring does not spend a second afternoon rediscovering them. Everything not on this list is expected to be covered; a new uncovered region is a gap, not a member of this set.

**How the figure is measured.** From the repository root:

```sh
swift test --enable-code-coverage --no-parallel
BIN_PATH=$(swift build --show-bin-path)
TEST_BINARY=$(find "$BIN_PATH" -type f -path "*Tests.xctest/Contents/MacOS/*" ! -path "*.dSYM/*" | head -n 1)
xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$BIN_PATH/codecov/default.profdata" \
    $(find Sources -name "*.swift" | sort)
```

The `TOTAL` row of that report is the one source of the figure above, and the rows with a missed region are the files to look in. To see where in a file, `xcrun llvm-cov show "$TEST_BINARY" -instr-profile "$BIN_PATH/codecov/default.profdata" <file> -show-regions`, or the regions with a zero count and kind 0 (code regions) in `xcrun llvm-cov export` over the same files. Two things make other counts differ:

- **The report's line column is not the line coverage.** It counts the lines of every function it instantiates, so a closure or autoclosure that never runs — the fallback of a `??` — shows as a missed function with a missed line, while the lcov export the Sonar analysis imports folds that line into the function around it. Line coverage from the lcov is 8266 of 8267; the line left is the `_exit` below.
- **Passing a function as an argument is a region.** `uniquingKeysWith: Uniquing.first` or `isAlive: ProcessTree.isAlive` compile to a thunk that only runs when the function is called — for a uniquing rule, only on a duplicate key. That is why `Uniquing` builds its dictionaries with loops rather than taking a function.

Each entry was tried before it was listed. The rule from #95 applies: a region that cannot be made to fail under a negative control is a candidate for deletion, not for a test. Going from 71 missed regions to six (#154), fallbacks no input reaches were deleted or rewritten without the optional — the shard error's missing description, the locator's non-usage errors and its child-path `?? name`, a protocol name in a declaration path, an empty ternary slice, the instrumenter's substring, the integrity reason, the shard balance's `min`, a merge's second search for missing verdicts, the warm Xcode path's content and result-bundle listing, a SARIF rule index looked up with a fallback, and an `.expr` item that is an `if` or `switch`, which the parser never produces — and the rest were covered by tests.

**Failure arms of system calls that macOS does not produce** — none left

This group used to hold ten regions: `sysctl` failing, `realpath` failing, `FileManager.enumerator(at:)` returning `nil`, `xcode-select -p` failing to run or printing bytes that are not text, the IOKit assertion table being absent or misshapen, a plist that cannot be written back, and the runner's own capture file being unreadable. `FileManager.enumerator(at:)` was measured rather than assumed: it returns a non-`nil` enumerator for a regular file, a path that does not exist, and a directory the user cannot read. `XMLParser(contentsOf:)` was measured the same way: it is never `nil` for a file URL, so the locator reads the workspace's contents file first and parses the data.

All ten are covered now, by the same move each time: the failing call is a parameter that defaults to the real call, so no production site changes, and the `try?`/`??` stays at the call site so a test can hand in a failing one and watch the arm fire. `ProcessRunner` takes the function that reads the capture file back and the check that a task was cancelled while its process started; `XCTestRunPlist.activating` takes the serializer; `SleepInhibitor.isHeld` takes the function that fetches the assertion table; `TestFilesHasher` takes the enumerator; `ProcessTree.descendants` takes `sysctl`; `DeveloperToolchain.resolveDeveloperPath` takes the executable to run; `ApplicationVerifier` takes the function it reads files with; and `realpath` moved out of `MutantExecutor` into `CanonicalPath.make(for:resolve:)`, which takes the resolver. The function typealiases live in `SystemCalls`. The same move covered the two launchers' `guard pid > 0`.

**Guards an earlier check in the same function already makes impossible**

| file | line | why it cannot be reached |
|---|---|---|
| `Discovery/Pipeline/FileDiscoveryStage.swift` | 48 | `sourcesPath` was checked for existence at the top of `run`, and the enumerator is never `nil` |
| `Discovery/Operators/ArithmeticOperatorVisitor.swift` | 58 | the operator is looked up by position in the list that contains it |
| `Discovery/Schematization/SchemataGenerator.swift` | 23 | a body's offsets, moved by the edits after them, always fall inside the buffer they were taken from |
| `Infrastructure/XCTestRunPlist.swift` | 24 | `init?` already refused data that is not a `[String: Any]` |
| `Infrastructure/ProcessTree.swift` | 18 | the process table has no cycles, so no pid is visited twice |

These stay because removing them replaces a graceful degrade with a crash or a force-unwrap. They are not free — each is a line that can rot without anyone noticing — which is why they are written down rather than left to be rediscovered.

**Race guards that cannot be provoked deterministically** — none left

Three regions used to sit here: `guard pid > 0` in both launchers' timeout handlers, and `SimulatorPool.cancelPending` being asked to cancel a request that was already resumed. The launchers' guard is what stands between a run cancelled before its process exists and `kill(-0, SIGTERM)`, which would signal the tool's own process group; it is covered by handing the static `terminate(pid:…)` a recording `kill` and asserting that pid 0 sends nothing. `cancelPending` was simply made non-private so a test can call it with an id that was never queued, which is the one place on this page where coverage was bought with a visibility change rather than an injected call.

**The entry point**

| file | line | why |
|---|---|---|
| `Sandbox/SandboxCleaner.swift` | 18 | `SignalTarget.process` exits through `_exit`, which would end the test process |

Covering that one means running the binary as a child process, sending it `SIGINT` and asserting on the exit code and the sandbox it left behind — an integration test, not a unit test. `InterruptedRunIntegrationTests` does run the binary that way, but `_exit` skips the code that writes the coverage profile, so the region stays missed. Passing `_exit` without the closure is not possible either: its type is `(Int32) -> Never`, which Swift does not convert to the `(Int32) -> Void` the target takes.
