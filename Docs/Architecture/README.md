# Architecture Documentation

`swift-mutation-testing` is a CLI for mutation testing of Swift projects (Xcode and SPM). It covers the full cycle: discovery (source file collection, AST parsing, mutant identification, indexing, schematization, incompatible rewriting) followed by execution (sandbox creation, build, parallel test execution, result reporting). Between the two sits the plan: discovery written down, so a run can be split into shards, merged, resumed or reproduced one mutant at a time.

## Documents

| Document | Contents |
|---|---|
| [01 — Overview](01-overview.md) | Purpose, module map, commands, entry point, exit codes |
| [02 — Discovery Pipeline](02-discovery.md) | Stages, mutation operators and tiers, suppression, infinite-loop prevention, inactive `#if` branches |
| [03 — Execution Pipeline](03-execution.md) | Sandbox, build, simulators, the baseline probe, three-pass test execution, fallback and incompatible mutants, result parsing, caching, reporting |
| [04 — Configuration](04-configuration.md) | Configuration model, YAML format and validation, CLI arguments, project detection |
| [05 — Schematization](05-schematization.md) | Embedding mutants into a single binary, per-file support declarations, runtime activation, the activation marker |
| [06 — Plans](06-plans.md) | The plan as the first decision written down: staleness, shards, merge, resuming, reproduce |

## Quick Reference

```
swift-mutation-testing [run] [<project-path>] [options]
swift-mutation-testing init [<project-path>]
swift-mutation-testing plan [<project-path>] --output <plan.json> [options]
swift-mutation-testing run [<project-path>] --plan <plan.json> [--shard <i/n>] [options]
swift-mutation-testing merge <result.json>... --plan <plan.json> [--project-path <path>] [options]
swift-mutation-testing reproduce <mutant> [<project-path>] [--plan <plan.json>] [options]
swift-mutation-testing --help | --version
```

**Exit codes:** `0` success · `1` error · `2` quality gate failed
