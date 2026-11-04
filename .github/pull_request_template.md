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
- [ ] build: Changes that affect the build system or external dependencies, including dependency version upgrades.
- [ ] style: Formatting changes that do not affect behavior.
- [ ] chore: Other changes that do not fit into the previous categories.
- [ ] revert: Reverts a previous commit.

## Invariants Checklist

- [ ] Original project is never modified — all mutations happen inside an isolated sandbox
- [ ] The schema is built once for all schematizable mutants (`xcodebuild build-for-testing` or `swift build --build-tests`), and again only to narrow it or split it into batches
- [ ] No mutant results are lost or duplicated
- [ ] Mutant positions (file, line, column) are accurate in all reported results
- [ ] A cancelled task never leaves a simulator slot permanently acquired from the pool
- [ ] Every schematized file declares its own support block, `@usableFromInline internal` and named after the file (the `__SwiftMutationTesting_<hash>` enum and its `__swiftMutationTestingID_<hash>` accessor), and nothing else in the sandbox declares it
- [ ] Swift 6 Strict Concurrency compatible
- [ ] Pipeline stages remain stateless pure transformations

## Pipeline Impact

Which stages are affected?

- [ ] Discovery / Schematization
- [ ] SandboxFactory / WarmSandboxes
- [ ] BuildStage / SchemaNarrower
- [ ] SimulatorPool
- [ ] MutantExecutor / TestExecutionStage
- [ ] IncompatibleMutantExecutor
- [ ] FallbackExecutor
- [ ] CacheStore / TestCoverage
- [ ] Reporters (Text / JSON / HTML / Sonar / SARIF / Markdown / Timing)
- [ ] Quality gate / Baseline
- [ ] Plans (plan / shard / merge / reproduce)
- [ ] CLI / Configuration
- [ ] Models / RunnerInput contract
- [ ] None

## Testing

- [ ] Unit tests added or updated
- [ ] Tests use mock `ProcessLaunching` — no real `xcodebuild`, `xcrun simctl`, or `xcresulttool`
- [ ] Tests use `FileHelpers` for any filesystem interaction (temp directories only)
- [ ] Snapshot tests added or updated (if reporter output format changed)
- [ ] Integration tests added or updated and tagged separately (if pipeline or CLI behavior changed)
- [ ] All tests pass locally (`swift test --no-parallel`)
