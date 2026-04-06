# Swift Mutation Testing

[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fericodx%2Fswift-mutation-testing%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ericodx/swift-mutation-testing)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fericodx%2Fswift-mutation-testing%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ericodx/swift-mutation-testing)
[![CI](https://img.shields.io/github/actions/workflow/status/ericodx/swift-mutation-testing/main-analysis.yml?branch=main&style=flat-square&logo=github&logoColor=white&label=CI&color=4CAF50)](https://github.com/ericodx/swift-mutation-testing/actions)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=deploy-on-friday-swift-mutation-testing&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=deploy-on-friday-swift-mutation-testing)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=deploy-on-friday-swift-mutation-testing&metric=coverage)](https://sonarcloud.io/summary/new_code?id=deploy-on-friday-swift-mutation-testing)
![mutation score](https://img.shields.io/badge/mutation%20score-85%25-lightgray?logo=jest&logoColor=white)

**Measure and improve test effectiveness in Swift codebases using mutation testing.**

`swift-mutation-testing` is a CLI for mutation testing of Swift projects — both Xcode and Swift Package Manager. It modifies your source code in small, targeted ways — mutations — and runs your test suite against each one. A mutation that goes undetected reveals missing tests or weak assertions. The result is a mutation score that reflects how effectively your tests catch real bugs.

## Why

Traditional test coverage does not guarantee that tests catch real bugs.

Mutation testing introduces controlled changes to your code to verify that your tests fail when behavior changes. Surviving mutations indicate gaps in test effectiveness.

## Features

- Mutation testing for Xcode and SPM projects
- Supports both XCTest and Swift Testing frameworks
- 7 mutation operators (relational, boolean, logical, arithmetic, negate conditional, swap ternary, remove side effects)
- Schematization — builds once, tests all mutants via runtime switch
- Parallel test execution with configurable concurrency
- SHA256-based result caching across runs
- Multiple report formats: text, JSON (Stryker-compatible), HTML, SonarQube
- Simulator pool management for iOS/tvOS/watchOS targets
- Per-scope mutation suppression via `@SwiftMutationTestingDisabled`
- Configurable via YAML or CLI flags
- CI/CD ready with caching support

## Install

```bash
brew tap ericodx/homebrew-tools
brew install swift-mutation-testing
```

Other installation methods — pre-built binary, build from source — are covered in the [Installation Guide](Docs/INSTALLATION.MD).

## Quick start

```bash
# Generate a config file (auto-detects project type, scheme, destination, and test targets)
swift-mutation-testing init

# Run mutation testing
swift-mutation-testing

# Run on an SPM package (no scheme or destination needed)
swift-mutation-testing /path/to/my-package
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

**Xcode project:**

```yaml
scheme: MyApp
destination: platform=iOS Simulator,name=iPhone 16
# testTarget: MyAppTests
# timeout: 120
# concurrency: 4
```

**SPM package** (scheme and destination are not needed):

```yaml
# testTarget: MyPackageTests
# timeout: 30
# concurrency: 4
```

**Mutation operators** (both project types — all active by default):

```yaml
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
