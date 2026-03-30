# Swift Mutation Testing

[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fericodx%2Fswift-mutation-testing%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ericodx/swift-mutation-testing)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fericodx%2Fswift-mutation-testing%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ericodx/swift-mutation-testing)
[![CI](https://img.shields.io/github/actions/workflow/status/ericodx/swift-mutation-testing/main-analysis.yml?branch=main&style=flat-square&logo=github&logoColor=white&label=CI&color=4CAF50)](https://github.com/ericodx/swift-mutation-testing/actions)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=deploy-on-friday-swift-mutation-testing&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=deploy-on-friday-swift-mutation-testing)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=deploy-on-friday-swift-mutation-testing&metric=coverage)](https://sonarcloud.io/summary/new_code?id=deploy-on-friday-swift-mutation-testing)

**Measure and improve test effectiveness in Swift codebases using mutation testing.**

`swift-mutation-testing` is a CLI for mutation testing of Xcode + XCTest projects. It modifies your source code in small, targeted ways — mutations — and runs your test suite against each one. A mutation that goes undetected reveals missing tests or weak assertions. The result is a mutation score that reflects how effectively your tests catch real bugs.

## Why

Traditional test coverage does not guarantee that tests catch real bugs.

Mutation testing introduces controlled changes to your code to verify that your tests fail when behavior changes. Surviving mutations indicate gaps in test effectiveness.

## Features

- Mutation testing for Xcode + XCTest projects
- Measures test effectiveness through mutation score
- Supports multiple mutation operators
- Provides detailed reports per file and mutation
- Configurable via YAML
- Can be integrated into CI pipelines

## Install

```bash
brew tap ericodx/homebrew-tools
brew install swift-mutation-testing
```

Other installation methods — pre-built binary, build from source — are covered in the [Installation Guide](Docs/INSTALLATION.MD).

## Quick start

```bash
# Generate a config file (auto-detects scheme and destination)
swift-mutation-testing init

# Run mutation testing
swift-mutation-testing
```

Example output:

```
  ✓ Discovery: 147 mutants (143 schematizable, 4 incompatible) in 2.3s

Building for testing...
  ✓ Built in 18.4s
  ✓ 3 simulators ready

Testing mutants...
  ✓ 1/147  RelationalOperatorReplacement  Validator.swift:18
  ✗ 2/147  NegateConditional              Validator.swift:34
  ✓ 3/147  BooleanLiteralReplacement      FeatureFlags.swift:9

Results by file:
  Sources/Validator.swift      score: 72.4%   killed: 21   survived: 8   timeout: 0   unviable: 0
  Sources/FeatureFlags.swift   score: 100.0%  killed: 6    survived: 0   timeout: 0   unviable: 0

Survived mutants:
  Sources/Validator.swift:34:5   NegateConditional

Overall mutation score: 83.2%
Killed: 122 / Survived: 21 / Timeouts: 0 / Unviable: 4 / NoCoverage: 0
Total duration: 312.7s
```

## Configuration

Drop a `.swift-mutation-testing.yml` in the project root:

```yaml
scheme: MyApp
destination: platform=iOS Simulator,name=iPhone 16
# testTarget: MyAppTests
timeout: 60
# concurrency: 4

# Mutation operators — set active: false to disable
mutators:
  - name: RelationalOperatorReplacement
    active: true
  - name: BooleanLiteralReplacement
    active: true
  - name: LogicalOperatorReplacement
    active: true
  - name: ArithmeticOperatorReplacement
    active: true
  - name: NegateConditional
    active: true
  - name: SwapTernary
    active: true
  - name: RemoveSideEffects
    active: true
```

Full reference in the [Usage & Configuration Guide](Docs/USAGE.MD).

## Documentation

| Document | Description |
|---|---|
| [Installation](Docs/INSTALLATION.MD) | Homebrew, pre-built binary, build from source |
| [Usage & Configuration](Docs/USAGE.MD) | CLI options, YAML config, output formats, CI integration |
| [Mutation Results](Docs/MUTATION-RESULTS.md) | What each result means and when it occurs; schematizable vs incompatible mutants |
| [Architecture](Docs/Architecture/README.md) | Pipeline design, module map, schematization, execution model |
| [Codebase Reference](Docs/CodeBase/README.md) | Every type, protocol, and stage documented |
| [Stryker Compatibility](Docs/STRYKER-COMPATIBILITY.md) | JSON report format compatibility with the Stryker schema |
