# Architecture Documentation

`swift-mutation-testing` is a CLI for mutation testing of Xcode + XCTest projects. It covers the full cycle: discovery (source file collection, AST parsing, mutant identification, schematization) followed by execution (sandbox creation, build, parallel test execution, result reporting).

## Documents

| Document | Contents |
|---|---|
| [01 — Overview](01-overview.md) | Purpose, module map, entry point, exit codes |
| [02 — Discovery Pipeline](02-discovery.md) | Stages, mutation operators, suppression |
| [03 — Execution Pipeline](03-execution.md) | Sandbox, build, simulators, test execution, result parsing, caching, reporting |
| [04 — Configuration](04-configuration.md) | Configuration model, YAML format, CLI arguments, project detection |
| [05 — Schematization](05-schematization.md) | Embedding mutants into a single binary, support file injection, runtime activation |

## Quick Reference

```
swift-mutation-testing [<project-path>] --scheme <scheme> --destination <destination>
swift-mutation-testing [<project-path>] init
```

**Exit codes:** `0` success · `1` error
