## Summary

<!-- What does this change do? Keep it concise. -->

## Type of Change

- [ ] feat: A new feature has been added.
- [ ] fix: A bug has been fixed.
- [ ] perf: A code change that improves performance.
- [ ] refactor: A code change that neither fixes a bug nor adds a feature.
- [ ] test: Addition or correction of tests.
- [ ] docs: Changes only to the documentation.
- [ ] ci: Changes related to continuous integration and deployment scripts.
- [ ] build: Changes that affect the build system or external dependencies.
- [ ] chore: Other changes that do not fit into the previous categories.
- [ ] revert: Reverts a previous commit.

## Invariants Checklist

- [ ] Original project is never modified — all mutations happen inside an isolated sandbox
- [ ] `xcodebuild build-for-testing` runs exactly once for all schematizable mutants
- [ ] No mutant results are lost or duplicated
- [ ] Mutant positions (file, line, column) are accurate in all reported results
- [ ] A cancelled task never leaves a simulator slot permanently acquired from the pool
- [ ] `schematizedContent` never contains the `__swiftMutationTestingID` global declaration
- [ ] Swift 6 Strict Concurrency compatible
- [ ] Pipeline stages remain stateless pure transformations

## Pipeline Impact

Which stages are affected?

- [ ] SandboxFactory
- [ ] BuildStage
- [ ] SimulatorPool
- [ ] TestExecutionStage
- [ ] IncompatibleMutantExecutor
- [ ] PerFileBuildFallback
- [ ] CacheStore
- [ ] Reporters (Text / JSON / HTML / Sonar)
- [ ] CLI / Configuration
- [ ] Models / RunnerInput contract
- [ ] None

## Testing

- [ ] Unit tests added or updated
- [ ] Tests use mock `ProcessLaunching` — no real `xcodebuild`, `xcrun simctl`, or `xcresulttool`
- [ ] Tests use `FileHelpers` for any filesystem interaction (temp directories only)
- [ ] Snapshot tests added or updated (if reporter output format changed)
- [ ] Integration tests added or updated and tagged separately (if pipeline or CLI behavior changed)
- [ ] All tests pass locally (`swift test`)
