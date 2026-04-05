# CodeBase Reference

Type-level reference for every public and internal type in `swift-mutation-testing`. Each document covers one module or cohesive group of types.

---

## Index

| Document | Coverage |
|---|---|
| [01 — Entry Point](01-entry-point.md) | `SwiftMutationTesting`, `ExitCode`, `HelpText`, `UsageError` |
| [02 — Configuration](02-configuration.md) | `CommandLineParser`, `ParsedArguments`, `RunnerConfiguration`, `BuildOptions`, `ReportingOptions`, `FilterOptions`, `ProjectType`, `TestingFramework`, `ConfigurationResolver`, `ConfigurationFileParser`, `ConfigurationFileWriter`, `ProjectDetector`, `DetectedProject` |
| [03 — Discovery Pipeline](03-discovery-pipeline.md) | `DiscoveryPipeline`, `DiscoveryInput`, `FileDiscoveryStage`, `FileDiscoveryError`, `ParsingStage`, `MutantDiscoveryStage`, `MutantIndexingStage`, `SchematizationStage`, `IncompatibleRewritingStage`, `SourceFile`, `ParsedSource`, `MutationPoint`, `IndexedMutationPoint`, `MutantDescriptor` |
| [04 — Mutation Operators](04-mutation-operators.md) | `MutationOperator`, `MutationSyntaxVisitor`, `ReplacementKind`, all 7 operator structs and visitors, `SuppressionAnnotationExtractor`, `SuppressionFilter`, `SuppressionVisitor` |
| [05 — Schematization](05-schematization.md) | `SchemataGenerator`, `MutationRewriter`, `TypeScopeVisitor`, `FunctionBodyScope`, `SchematizedFile` |
| [06 — Sandbox & Build](06-sandbox-build.md) | `SandboxFactory`, `Sandbox`, `BuildStage`, `BuildArtifact`, `BuildError` |
| [07 — Execution](07-execution.md) | `MutantExecutor`, `ExecutionDeps`, `TestExecutionStage`, `TestExecutionContext`, `TestLaunchResult`, `FallbackExecutor`, `IncompatibleMutantExecutor`, `SimulatorPool`, `SimulatorSlot`, `SimulatorManager`, `SimulatorError`, `MutationCounter`, `RunnerInput`, `ExecutionResult`, `ExecutionStatus` |
| [08 — Result Parsing & Cache](08-result-parsing-cache.md) | `TestResultResolver`, `ResultParser`, `SPMResultParser`, `TestRunOutcome`, `TestOutputParser`, `XCResultParser`, `CacheStore`, `MutantCacheKey` |
| [09 — Reporting & Infrastructure](09-reporting-infrastructure.md) | `ProgressReporter`, `ConsoleProgressReporter`, `SilentProgressReporter`, `RunnerEvent`, `RunnerSummary`, `TextReporter`, `JsonReporter`, `HtmlReporter`, `SonarReporter`, all `MutationReport*` types, all `Sonar*` types, `ProcessLaunching`, `ProcessRunner`, `ProcessRequest`, `SPMProcessLauncher`, `XCTestRunPlist`, `TestFilesHasher` |

---

## Quick Reference

### Value flow between pipelines

```
DiscoveryInput
  → FileDiscoveryStage        → [SourceFile]
  → ParsingStage              → [ParsedSource]
  → MutantDiscoveryStage      → [MutationPoint]
  → MutantIndexingStage       → [IndexedMutationPoint]
  → SchematizationStage       → [SchematizedFile], [MutantDescriptor]
  → IncompatibleRewritingStage → [MutantDescriptor]
  → RunnerInput

RunnerInput
  → SandboxFactory → Sandbox
  → BuildStage     → BuildArtifact
  → TestExecutionStage → TestResultResolver → [ExecutionResult]
  → FallbackExecutor (on build failure)     → [ExecutionResult]
  → IncompatibleMutantExecutor              → [ExecutionResult]
  → RunnerSummary
  → Reporters
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
