# Building for Contributors

This guide is for contributors who need to build, test, and smoke-test
`swift-mutation-testing` from a local checkout. Installation options for users
are covered in [Installation](INSTALLATION.MD).

## Prerequisites

- macOS 15 or later
- Xcode 26 or later
- Swift 6.2 or later (`Package.swift` declares `swift-tools-version: 6.2`)
- Git
- pre-commit, for local repository hooks

Verify the Swift toolchain before running package commands:

```bash
swift --version
```

## Build and Test

Run a debug build for day-to-day development:

```bash
swift build
```

Run the test suite:

```bash
swift test --no-parallel
```

Always `--no-parallel`, which is what CI does. Several tests capture stdout or
drive real processes, and two of them running at once read each other's
output.

`swift test --enable-code-coverage --no-parallel` also writes a coverage
profile. On every push to `main`, CI turns that profile into the report
SonarCloud reads. Region coverage is the number that matters here: the
commands that print it from the profile, and the regions the suite
deliberately leaves uncovered with a reason each, are in
[Docs/CodeBase/README.md](CodeBase/README.md#regions-the-suite-deliberately-does-not-cover).
Anything uncovered that is not on that list is a gap.

The suite includes unit tests and fixture-backed integration coverage. If the
toolchain is older than the version required by `Package.swift`, upgrade Swift
before trusting the result.

## CLI Smoke Checks

Use `swift run` so the executable comes from the checkout under test:

```bash
swift run swift-mutation-testing --help
swift run swift-mutation-testing --version
swift run swift-mutation-testing init Fixtures/CalcLibrary
```

The `init` command should generate a `.swift-mutation-testing.yml` file for the
fixture project. Remove that generated file before committing if you create it
inside the repository.

## Fixture Projects

The repository includes small projects for local validation:

- `Fixtures/CalcLibrary` is a Swift Package Manager fixture.
- `Fixtures/CalcApp` is an Xcode project fixture.
- `Fixtures/CalcModules` is a Swift Package Manager fixture with two library
  targets and a test target for each. The multi-module integration test runs
  it and checks that one build tests every mutant of both modules.
- `Fixtures/CalcWorkspace` is an Xcode workspace fixture, for the workspace
  integration tests.

Run the SPM fixture without a scheme or destination:

```bash
swift run swift-mutation-testing Fixtures/CalcLibrary
```

Run the Xcode fixture with its scheme and macOS destination:

```bash
swift run swift-mutation-testing Fixtures/CalcApp \
  --scheme CalcApp \
  --destination "platform=macOS"
```

## Claude Code Plugin

`.claude-plugin/` and `skills/` make the repository a Claude Code plugin
marketplace. After changing either, validate them with the Claude Code CLI:

```bash
claude plugin validate .
```

The only expected warning is the missing `version`. It is left out on purpose:
without it, Claude Code versions the plugin by commit, so users receive a new
skill as soon as it reaches `main`, instead of staying on a pinned copy.
`PluginManifestTests` checks the manifests and the skill's frontmatter in
`swift test`.

To try the skill before merging, load the checkout for one session:

```bash
claude --plugin-dir .
```

## Repository Hooks

Install the configured hooks before preparing commits:

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

The hook set includes conventional commit validation, common file checks,
codespell, SwiftLint, swift-format, Swift code duplication detection,
Swift Marshal, and Gitleaks. Swift source changes should pass SwiftLint and
swift-format before review.

To run all hooks on the current checkout:

```bash
pre-commit run --all-files
```
