# Usage & Configuration Guide

This guide covers every way to run and configure `swift-mutation-testing`, from a first run to full CI integration.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Configuration File](#configuration-file)
3. [CLI Reference](#cli-reference)
4. [Plans](#plans) — shard a run across machines, merge, resume, reproduce one mutant
5. [Parallelism](#parallelism)
6. [Output Formats](#output-formats)
7. [Suppressing Mutations](#suppressing-mutations)
8. [Quality Gate](#quality-gate)
9. [CI/CD Integration](#cicd-integration)
10. [Exit Codes](#exit-codes)

---

## Quick Start

### Generate a configuration file

```bash
# Auto-detects project type, scheme, destination, test targets, and testing framework
swift-mutation-testing init
```

This writes `.swift-mutation-testing.yml` at the project root. Review and adjust the generated file before running. For SPM packages, `scheme` and `destination` are not required and will be omitted. `init` never overwrites: when the file already exists it stops with exit code `1`.

### Run mutation testing

```bash
swift-mutation-testing
```

### Run an SPM package

```bash
# SPM packages are auto-detected — no scheme or destination needed
swift-mutation-testing /path/to/my-package
```

### Run on macOS without a simulator

```bash
swift-mutation-testing \
  --scheme MyScheme \
  --destination "platform=macOS"
```

### Run an Xcode workspace

A workspace — several projects, CocoaPods, or local packages next to the app — is built as such, with `-workspace`. Without a flag the tool looks at the project root: one `.xcworkspace` is the container, otherwise one `.xcodeproj`. Two candidates of the same kind stop the run before anything is built, naming them, rather than letting the directory order choose:

```
found App.xcworkspace and Tools.xcworkspace at the project root; pass --workspace (or the `workspace` key) to choose one
```

Name the container with `--workspace` or `--project` (or the `workspace` / `project` keys), relative to the project root; it may sit in a subdirectory. A root with no container of its own is never built blind either: when workspaces or projects sit below it, the run stops and lists them (`found Apps/App.xcworkspace … below it; pass --workspace or --project`). `init` writes the one it finds, so the generated file runs as is; when it cannot choose, it writes the reason and every candidate, commented out, for you to pick.

```bash
swift-mutation-testing --workspace Apps/App.xcworkspace --scheme App --destination "platform=macOS"
```

Every project of the workspace is schematized in the one build, whichever project or module a mutant is in, and every SwiftLint build phase in every project of the sandbox is switched off, so a linter does not fail the build on generated code. Two limits:

- **Projects outside the root.** A workspace that references a project outside the project root (`../Shared/Shared.xcodeproj`) is refused with the list of such projects: the sandbox holds only the root. Run from a directory that contains every project of the workspace.
- **CocoaPods.** `Pods/` reaches the sandbox by symlink and is never mutated only if it is out of scope: keep it outside `--sources-path`, or add `--exclude /Pods/`.

### Run on iOS Simulator

```bash
swift-mutation-testing \
  --scheme MyApp \
  --destination "platform=iOS Simulator,name=iPhone 16"
```

### First-time output

```
  ✓ Discovery: 147 mutants (143 schematizable, 4 incompatible) in 2.3s

Building for testing...
  ✓ Built in 18.4s
  ✓ 3 simulators ready

Testing mutants...
  ✓ 1/147  NegateConditional           Calculator.swift:12
  ✗ 2/147  LogicalOperatorReplacement  Validator.swift:34
  ✓ 3/147  SwapTernary                 FeatureFlags.swift:8
  ...

Results by file:
  Sources/Calculator.swift    score: 95.0%   killed: 19   survived: 1   timeout: 0   unviable: 0   no coverage: 0
  Sources/Validator.swift     score: 72.4%   killed: 21   survived: 8   timeout: 0   unviable: 0   no coverage: 0

Undetected mutants:
  Sources/Validator.swift:34:5   LogicalOperatorReplacement   survived
  Sources/Validator.swift:67:12  NegateConditional            survived
  ...

Overall mutation score: 85.3%
Detected: 122 (killed 122, timeout 0) / Undetected: 21 (survived 21, no coverage 0)
Killed: 122 / Survived: 21 / Timeouts: 0 / Unviable: 4 / NoCoverage: 0
Total duration: 5m 12s
```

A run, and `reproduce`, keep the Mac from idle sleep until they finish.

---

## Configuration File

Generate a starter file with:

```bash
swift-mutation-testing init
```

### Full reference

Every key the file accepts. `init` writes the same layout, filling in what it detects and leaving the rest commented out; the `operators` and `disabled-mutators` lines are not part of what it writes. Comments show the default value for each optional field.

```yaml
# swift-mutation-testing configuration
# All settings are optional. CLI flags override file values.

# The .xcworkspace or the .xcodeproj to build, relative to the project (one of them)
# workspace: MyApp.xcworkspace
# project: MyApp.xcodeproj

scheme: MyApp
destination: platform=iOS Simulator,name=iPhone 16

# Limit test execution to a specific target (recommended when the project has UI tests)
# test-target: MyAppTests

# Per-mutant test timeout in seconds (default: 120 Xcode, 30 SPM).
# Applies to the run that decides a verdict; the first, parallel pass allows twice this.
timeout: 60

# Build timeout in seconds (default: 120)
# build-timeout: 240

# Number of parallel workers (default: max(1, CPU count - 1))
# concurrency: 4

# Which testing library a mutant's tests run with: xctest or swift-testing (default: swift-testing)
# testing-framework: swift-testing

# Disable result cache (re-runs all mutants on every execution)
# no-cache: true

# Suppress progress output
# quiet: true

# Directory for source discovery, or a single .swift file (default: the project path)
# sources-path: Sources

# Report output paths
# output: mutation-report.json
# html-output: mutation-report.html
# sonar-output: sonar-mutation-report.json
# sarif-output: mutation-report.sarif
# markdown-output: mutation-summary.md

# Write each mutant's captured test output to <dir>/<mutant-id>.log
# keep-logs: .mutation-logs

# Files to leave out: a glob (**/Generated/**) or a fragment of the path (/Generated/)
# exclude:
#   - "**/Generated/**"

# Quality gate — a failed gate exits with code 2
# min-score: 80
# Baseline written by --write-baseline, relative to the project
# baseline: .swift-mutation-testing-baseline.json
# max-score-drop: 2
# max-new-survivors: 0
# Mutants killed or timed out without the mutated code running
# max-integrity-warnings: 0

# Operators up to this tier run: conservative, default or experimental.
# operator-tier: default

# Or the operators to run, whatever their tier; or the ones to leave out of the tier's set
# operators: NegateConditional, SwapTernary
# disabled-mutators: SwapTernary

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

### File syntax

The file is read line by line, not by a full YAML parser:

- A key is `key: value` at the start of a line. Keys are kebab-case, as in the table below. A key the tool does not know is ignored with a warning (`Warning: unknown key 'treshold' in .swift-mutation-testing.yml is ignored`), so a misspelt key does not pass unnoticed.
- A list is either `- item` lines under the key or one comma-separated value (`exclude: /Generated/, /Vendor/`).
- `#` starts a comment at the start of a line or after a space, outside quotes, so `timeout: 60  # seconds` reads `60`. Quotes around a value are removed.
- Values are checked before anything runs, and a bad one stops with exit code `1`, naming the key: `timeout` and `build-timeout` must be positive numbers, `concurrency` a whole number of at least 1, `min-score` between 0 and 100, `max-score-drop` 0 or more, `max-new-survivors` and `max-integrity-warnings` whole numbers of 0 or more. `no-cache` and `quiet` take `true`/`false`, `yes`/`no` or `on`/`off`.

### Field reference

| Field | Type | Default | Description |
|---|---|---|---|
| `scheme` | String | — | Xcode scheme to build and test (required for Xcode projects, omit for SPM) |
| `destination` | String | — | `xcodebuild` destination specifier (required for Xcode projects, omit for SPM) |
| `workspace` | String | the root's one container | The `.xcworkspace` to build, relative to the project. See [Run an Xcode workspace](#run-an-xcode-workspace) |
| `project` | String | the root's one container | The `.xcodeproj` to build, relative to the project. Not together with `workspace` |
| `test-target` | String | — | Limit test execution to this target: on a package, the test target whose bundle runs — `Tests/<target>/` builds `<target>.xctest`; on an Xcode project, `-only-testing` |
| `testing-framework` | String | `swift-testing` | `xctest` or `swift-testing` |
| `timeout` | Number | `120` (Xcode) / `30` (SPM) | Per-mutant test timeout in seconds. The first, parallel pass allows twice this |
| `build-timeout` | Number | `120` | Build timeout in seconds |
| `concurrency` | Number | `max(1, CPUs − 1)` | Parallel test workers, at least 1. Xcode on `platform=macOS`, and XCTest on a simulator, run one — see [Parallelism](#parallelism) |
| `no-cache` | Boolean | `false` | Disable result caching |
| `quiet` | Boolean | `false` | Suppress progress output |
| `output` | String | — | Path for Stryker-compatible JSON report |
| `html-output` | String | — | Path for the HTML report |
| `sonar-output` | String | — | Path for a SonarQube generic issue import report: undetected mutants as issues, read with `sonar.externalIssuesReportPaths` |
| `sarif-output` | String | — | Path for the SARIF 2.1.0 report of undetected mutants |
| `markdown-output` | String | — | Path for a Markdown summary, for CI job summaries |
| `keep-logs` | String | — | Directory for per-mutant test output logs, and for `baseline.log` when the unmutated suite fails |
| `sources-path` | String | project root | Directory for Swift source file discovery, or a single `.swift` file to mutate alone |
| `exclude` | List | `[]` | Files to skip: globs, or fragments of the path. See [Excluding files](#excluding-files). `exclude-patterns` is read as the same key |
| `disabled-mutators` | List | `[]` | Operator identifiers to skip — deny-list alternative to the `mutators` block |
| `mutators` | Block | — | Operator list with per-entry `active: true/false` (generated by `init`); `active: false` leaves the operator out of the tier's set |
| `operators` | List | the tier's set | Allowlist of operator identifiers, run whatever their tier |
| `operator-tier` | String | `default` | Run the operators up to this tier: `conservative`, `default` or `experimental`. See [OPERATORS.md](OPERATORS.md) |
| `min-score` | Number | — | Fail the run (exit code 2) when the score is below this, 0–100. See [Quality Gate](#quality-gate) |
| `baseline` | String | — | Baseline file to compare with, relative to the project |
| `max-score-drop` | Number | — | Fail when the score is more than this many points below the baseline's. Needs `baseline` |
| `max-new-survivors` | Number | — | Fail when more than this many undetected mutants are not in the baseline. Needs `baseline` |
| `max-integrity-warnings` | Number | — | Fail when more than this many mutants were killed or timed out without the mutated code running |

### Operator identifiers

| Identifier | What it mutates |
|---|---|
| `RelationalOperatorReplacement` | `>` `>=` `<` `<=` `==` `!=` |
| `BooleanLiteralReplacement` | `true` ↔ `false` |
| `LogicalOperatorReplacement` | `&&` ↔ `\|\|` |
| `ArithmeticOperatorReplacement` | `+` `-` `*` `/` `%` |
| `NegateConditional` | wraps conditions in `!()` |
| `SwapTernary` | swaps ternary branches |
| `RemoveSideEffects` | removes standalone function call statements |

### Operator tiers

Every operator has a tier — `conservative`, `default` or `experimental` — assigned from measured data in [OPERATORS.md](OPERATORS.md). A run takes the operators up to a tier: `conservative` is the smallest set (`LogicalOperatorReplacement`, `NegateConditional`, `SwapTernary`); `default` is, since the second run of the campaign, that same set; and `experimental` adds `BooleanLiteralReplacement`, `RelationalOperatorReplacement`, `RemoveSideEffects` and `ArithmeticOperatorReplacement` — high kill rates, but between a quarter and a third of their survivors are equivalent mutants. The default is `default`. Before tiers existed every operator ran, so a score from an older version and one from this one are not comparable; `--operator-tier experimental` gives the old set.

```yaml
operator-tier: experimental
```

The same choice on the command line is `--operator-tier experimental`.

### Operator configuration formats

Besides the tier, there are two ways to configure operators in the YAML file.

**`mutators` block** (generated by `init`) — deny-list style. Set `active: false` on the entries you want to skip; `active: true` leaves the tier's set as it is, so it does not add an operator the tier leaves out:

```yaml
mutators:
  - name: RelationalOperatorReplacement
    active: true
  - name: RemoveSideEffects
    active: false   # this operator will be skipped
```

**`operators` list** — allow-list style. Only the listed operators run; everything else is skipped:

```yaml
operators:
  - RelationalOperatorReplacement
  - BooleanLiteralReplacement
```

How the three settings combine, on the command line and in the file:

1. An explicit list — `--operator` or `operators` — runs exactly those operators, whatever their tier. The command line wins over the file.
2. Otherwise the tier's set runs — `--operator-tier`, else `operator-tier`, else `default` — minus every operator disabled by `--disable-mutator`, `disabled-mutators` or `active: false`, from the command line and the file alike. Disabling every operator of the tier is a usage error, exit code `1`; choose a larger `--operator-tier` instead.

Identifiers are case-sensitive, and one that names no operator is ignored without a warning: a list in which no name matches finds no mutant, and the run ends with exit code `1`.

---

## CLI Reference

### Subcommands

```bash
swift-mutation-testing [run] [project-path] [options]      # discover and test every mutant (the default)
swift-mutation-testing init [project-path]                 # generate .swift-mutation-testing.yml
swift-mutation-testing plan [project-path] [--output plan.json]  # write the plan (default: plan.json)
swift-mutation-testing run [project-path] --plan plan.json [--shard i/n]
swift-mutation-testing merge result.json... --plan plan.json [--project-path path] --output merged.json
swift-mutation-testing reproduce <fingerprint|id> [project-path] [--plan plan.json]
swift-mutation-testing --version
swift-mutation-testing --help
```

`plan`, `run --plan`, `--shard`, `merge` and `reproduce` are described under [Plans](#plans).

### Options

```bash
swift-mutation-testing [project-path] [options]
```

| Option | Description |
|---|---|
| `--scheme <scheme>` | Xcode scheme to build and test (required for Xcode, omit for SPM) |
| `--destination <destination>` | `xcodebuild` destination specifier (required for Xcode, omit for SPM) |
| `--workspace <path>` | The `.xcworkspace` to build, relative to the project; overrides the `workspace` or `project` key |
| `--project <path>` | The `.xcodeproj` to build, relative to the project; not together with `--workspace` |
| `--target <test-target>` | Limit test execution to this test target: its bundle on a package, `-only-testing` on an Xcode project |
| `--testing-framework <fw>` | `xctest` or `swift-testing` — which library a mutant's tests are run with (default: `swift-testing`). Auto-detected by `init`; on an SPM package the probe drops a library that has no tests anyway |
| `--timeout <seconds>` | Per-mutant test timeout, a positive number (default: 120 Xcode, 30 SPM) |
| `--build-timeout <seconds>` | Build timeout, a positive number (default: 120). Sandboxes never inherit `.build`, so every build is cold |
| `--concurrency <n>` | Parallel workers, at least 1 (default: CPUs − 1). Resolved to 1 for Xcode on `platform=macOS` and for XCTest — see [Parallelism](#parallelism) |
| `--no-cache` | Disable result caching — no verdict is read from the cache, and none is written back |
| `--keep-logs <dir>` | Write each mutant's captured test output to `<dir>/<mutant-id>.log`, and a failing baseline's output to `<dir>/baseline.log` |
| `--output <path>` | Write Stryker-compatible JSON report |
| `--html-output <path>` | Write the HTML report |
| `--sonar-output <path>` | Write a SonarQube generic issue import report (import it with `sonar.externalIssuesReportPaths`, not as coverage) |
| `--sarif-output <path>` | Write a SARIF 2.1.0 report of undetected mutants |
| `--markdown-output <path>` | Write a Markdown summary of the run and the quality gate |
| `--sources-path <path>` | Directory for source discovery, or a single `.swift` file — the quick way to re-check one file after adding a test. The usual exclusions still apply |
| `--exclude <pattern>` | Leave out the files a glob or a path fragment matches (repeatable). See [Excluding files](#excluding-files) |
| `--operator-tier <tier>` | Run the operators up to this tier: `conservative`, `default` or `experimental` (default: `default`) |
| `--operator <id>` | Run only this operator, whatever its tier (repeatable) |
| `--disable-mutator <id>` | Leave this operator out of the tier's set (repeatable) |
| `--quiet` | Suppress progress output |
| `--min-score <0-100>` | Fail the run (exit code 2) when the score is below this |
| `--baseline <path>` | Baseline to compare with, relative to the project |
| `--max-score-drop <points>` | Fail when the score is more than this many points below the baseline's |
| `--max-new-survivors <n>` | Fail when more than `n` (0 or more) undetected mutants are not in the baseline |
| `--max-integrity-warnings <n>` | Fail when more than `n` (0 or more) mutants were killed or timed out without the mutated code running |
| `--write-baseline <path>` | Write this run's baseline, relative to the project. Command line only |
| `--plan <plan.json>` | `run`: execute this plan instead of discovering, refusing it if the code changed. `merge`, `reproduce`: the plan to work from |
| `--shard <i/n>` | `run --plan` only: run the i-th of n slices of the plan, split by file |
| `--project-path <path>` | `merge` only: the project the merged report describes (default: the current directory) |
| `--version` | Print the version and the platform it was built for (`swift-mutation-testing 1.7.0 [arm64-macos15]`) and exit |
| `--help`, `-h` | Print the usage and exit (as the first argument) |

An option the tool does not know, a missing value, or a value of the wrong kind stops the run with exit code `1` before anything is built.

Report paths (`--output`, `--html-output`, `--sonar-output`, `--sarif-output`, `--markdown-output`) and `--keep-logs` are relative to the current directory; `--baseline` and `--write-baseline` are relative to the project. A report that cannot be written is a warning, not an error: the other reports are still written and the exit code is unchanged.

### Common invocations

```bash
# Run with config file (no extra flags needed)
swift-mutation-testing

# Override scheme and destination
swift-mutation-testing --scheme MyApp --destination "platform=macOS"

# Limit to a single test target
swift-mutation-testing --target MyAppTests

# Run only two operators
swift-mutation-testing \
  --operator RelationalOperatorReplacement \
  --operator BooleanLiteralReplacement

# Disable one operator, keep the rest
swift-mutation-testing --disable-mutator RemoveSideEffects

# Run every operator, including the experimental ones
swift-mutation-testing --operator-tier experimental

# Exclude generated code
swift-mutation-testing --exclude "Sources/Generated/**"

# Generate all report formats
swift-mutation-testing \
  --output mutation-report.json \
  --html-output mutation-report.html \
  --sonar-output sonar.json \
  --sarif-output mutation-report.sarif \
  --markdown-output mutation-summary.md

# Suppress progress output (useful in CI)
swift-mutation-testing --quiet

# Invalidate cache and run fresh
swift-mutation-testing --no-cache
```

---

## Plans

A run decides everything it will do before it builds anything: which files, which mutants, in which order. A **plan** writes that decision down — `swift-mutation-testing plan` — and `run --plan` executes it, on this machine or another, in one piece or in slices. The plain run without a plan still works exactly as before; it makes a plan in memory and runs it at once, so there is one path from mutants to verdicts whichever way you go.

A plan has no absolute path and no execution option in it: timeout, concurrency, cache and reports belong to the run. Two plans of the same code are the same bytes wherever they are made, and every result file names the plan it ran, so results can be joined and checked.

### Writing a plan

```bash
swift-mutation-testing plan --output plan.json
```

Discovery runs as in a normal run — the configuration file, `--sources-path`, `--exclude`, `--operator-tier`, `--operator` and `--disable-mutator` all apply — and the plan is written instead of built, to `--output`, or `plan.json` without it. A scope with no mutant writes no plan and exits with `1`. It is small enough to review in a pull request: one entry per mutant, with its file, position, operator, change and fingerprint, plus the SHA-256 of every source file in scope.

```json
{
  "files" : [ { "path" : "Sources/Foo.swift", "sha256" : "…" } ],
  "formatVersion" : 1,
  "mutants" : [
    {
      "column" : 17, "description" : "&& → ||", "file" : "Sources/Foo.swift", "fingerprint" : "3f2a…",
      "line" : 42, "operator" : "LogicalOperatorReplacement", "original" : "&&", "replacement" : "||",
      "replacementKind" : "binaryOperator", "schematizable" : true, "utf8End" : 1026, "utf8Start" : 1024
    }
  ],
  "project" : { "type" : "spm" },
  "scope" : { "excludePatterns" : [], "operators" : ["LogicalOperatorReplacement", "NegateConditional", "SwapTernary"], "sourcesPath" : "Sources" },
  "toolVersion" : "1.7.0"
}
```

Keys are sorted, and a key with no value is left out: an Xcode plan's `project` adds `scheme`, `destination` and the `workspace` or `xcodeProject` it builds, and `testTarget` appears when one is set.

### Running a plan

```bash
swift-mutation-testing run --plan plan.json --output result.json
```

The project, test target and scope come from the plan; the command line and the configuration file still set the execution options. Before anything is built, every file of the plan is hashed again: if one changed, the run stops with `plan is stale: Sources/Foo.swift changed since the plan was made; make the plan again`. A plan never runs over code other than the code it describes. The `toolVersion` in the plan is information, not a requirement; the `formatVersion` is checked.

### Sharding

```bash
swift-mutation-testing run --plan plan.json --shard 1/4 --output result-1.json
swift-mutation-testing run --plan plan.json --shard 2/4 --output result-2.json
# … on as many machines as there are shards
```

`--shard i/n` runs the i-th of n slices. The plan is split **by file**: all the mutants of a file go to one shard, so each shard builds one schema holding only its mutants and no file is built twice. Files are taken in path order and each goes to the shard with the fewest mutants so far, so the same plan and the same `n` always give the same slices; the balance is approximate, and a file with more mutants than its share still goes whole to one shard. A shard with no file is a valid, empty run.

### Merging

```bash
swift-mutation-testing merge result-1.json result-2.json result-3.json result-4.json \
    --plan plan.json --output mutation-report.json --html-output mutation-report.html
```

`merge` joins the shards' JSON reports into the reports of the whole run — every format, and the [quality gate](#quality-gate) runs over the merged result. Three rules, each an error:

- every result must come from the same plan (each report carries `config.planSha256`);
- no mutant may have a verdict in two results;
- every mutant of the plan must have a verdict. A missing shard is reported with the mutants it would have covered, and no score is given: a score over part of the plan would not be the number a single run gives.

`merge` reports on the project in the current directory, or on the one `--project-path <path>` names: its sources are embedded in the reports and its configuration file applies, so they must be the plan's sources. The result files are the positional arguments, which is why the project is a flag here.

### GitHub Actions matrix

```yaml
jobs:
  plan:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v6
      - run: brew tap ericodx/homebrew-tools && brew install swift-mutation-testing
      - run: swift-mutation-testing plan --output plan.json --quiet
      - uses: actions/upload-artifact@v4
        with: { name: plan, path: plan.json }

  shard:
    needs: plan
    runs-on: macos-15
    strategy:
      matrix: { shard: [1, 2, 3, 4] }
    steps:
      - uses: actions/checkout@v6
      - run: brew tap ericodx/homebrew-tools && brew install swift-mutation-testing
      - uses: actions/download-artifact@v4
        with: { name: plan }
      - run: swift-mutation-testing run --plan plan.json --shard ${{ matrix.shard }}/4 --output result-${{ matrix.shard }}.json --quiet
      - uses: actions/upload-artifact@v4
        with: { name: result-${{ matrix.shard }}, path: result-${{ matrix.shard }}.json }

  merge:
    needs: shard
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v6
      - run: brew tap ericodx/homebrew-tools && brew install swift-mutation-testing
      - uses: actions/download-artifact@v4
        with: { name: plan }
      - uses: actions/download-artifact@v4
        with: { pattern: result-*, merge-multiple: true }
      - run: |
          swift-mutation-testing merge result-*.json --plan plan.json \
            --output mutation-report.json --markdown-output mutation-summary.md \
            --baseline .swift-mutation-testing-baseline.json --max-new-survivors 0
```

The shards must check out the same commit the plan was made from; a different commit is a stale plan, and the shard says so.

### Resuming an interrupted run

Every verdict is written down the moment it is known, in two places. A run that ends early — `Ctrl+C`, a crash, a lost machine — leaves its verdicts behind, and the next run continues with the mutants that have none. Nothing to pass.

- **The cache's journal** (`.swift-mutation-testing-cache/journal.jsonl`) serves every run, planned or not. It is the cache doing its job, so it does not exist under `--no-cache`.
- **The plan's journal** (`.swift-mutation-testing-cache/plans/<plan hash>[-<i>-of-<n>].jsonl`) serves `run --plan`: one per plan and shard, read by the next `run --plan` of the same plan and shard, which runs only the mutants it has no verdict for (`✓ Resumed 4 verdicts from an interrupted run of this plan`) and removes the journal when it finishes. It is kept even under `--no-cache`: it holds only the progress of a run that did not finish, over files the plan's hashes pin, so a finished run leaves nothing behind and the next one measures everything again.

### Reproducing one mutant

```bash
swift-mutation-testing reproduce 3f2a9c1e --plan plan.json
swift-mutation-testing reproduce swift-mutation-testing_12      # by the id in a report, plan made in memory
```

`reproduce` runs one mutant — by fingerprint, by a prefix of it that fits one mutant, or by its report id — the way an investigation needs it: the whole suite, not the targeted tests first; no stop at the first failing test; the sandbox left in place. It prints the sandbox's path, the line before and after the mutation, the complete test output, and the verdict with its reason. The sandbox stays until the next run's sweep of orphaned sandboxes removes it; copy it if you need it longer.

---

## Parallelism

`--concurrency` is the number of mutants tested at once, where the run can isolate them:

| Run | Workers |
|---|---|
| SPM package | `--concurrency` |
| Xcode scheme on a simulator destination, Swift Testing | `--concurrency`, one simulator clone each |
| Xcode scheme on a simulator destination, XCTest | 1 |
| Xcode scheme on `platform=macOS` | 1 |

A package's mutants run the compiled test bundles directly, not through `swift test`, so the workers do not queue on the lock SwiftPM takes on `.build`. An Xcode run on a simulator destination gives each worker a simulator of its own: the destination's simulator is cloned once per worker (`✓ 3 simulators ready`) and the clones are deleted when the run ends. A destination with no `platform=`, or with a `Simulator` platform, counts as a simulator; `platform=macOS` has nothing to clone.

`--concurrency` is resolved down to 1 for the last two rows rather than accepted and quietly ignored, so the number the configuration reports is the number of mutants actually tested at once.

Two passes use fewer workers: mutants that timed out in the parallel pass are run again with a quarter of them, and incompatible mutants are built and tested on a quarter of them, each worker with a sandbox of its own that it builds once and then rebuilds incrementally — see [Mutation Results](MUTATION-RESULTS.md#performance-implications).

---

## Output Formats

### Per-mutant logs

`--keep-logs <directory>` writes what each mutant's tests printed, one file per mutant, named after the mutant id. Without it that output is parsed into a verdict and discarded, which leaves an unexpected verdict with nothing behind it to read.

```
mutant:    swift-mutation-testing_42
location:  /Users/me/MyPackage/Sources/Validator.swift:18:9
operator:  RelationalOperatorReplacement
mutation:  > → >=
status:    Crash
activated: yes, the mutated code ran
duration:  2.25s
---
<everything the test run printed>
```

`activated` says whether the mutant's own code ran during that test run: `yes`, `no` (a passing suite is then reported as no coverage; a failing one is an [integrity warning](MUTATION-RESULTS.md#integrity-warnings)), or `not measured` when the mutant could not be instrumented (see [No coverage](MUTATION-RESULTS.md#no-coverage-)).

`Crash` is the verdict worth reaching for this first: it is reachable three separate ways — a fatal error, a bad instruction, or test output naming no failing test — and the verdict alone does not say which.

Mutants reported `Unviable` get a log too, holding the output of the build that failed — or a note that the mutation could not be applied. That is the verdict which explains itself least, and on some packages it is the majority of a run.

One file is written per mutant, so a large run produces as many logs as it has mutants, each holding a full test-suite run. Point it somewhere disposable.

### Progress output (default)

Streams build events and per-mutant results to stdout during execution.

```
  ✓ Discovery: 147 mutants (143 schematizable, 4 incompatible) in 2.3s

Building for testing...
  ✓ Built in 18.4s
  ✓ 3 simulators ready

Testing mutants...
  ✓ 1/147  ArithmeticOperatorReplacement  Calculator.swift:12
  ✗ 2/147  RelationalOperatorReplacement  Validator.swift:34
  ⚠ 3/147  RemoveSideEffects              Service.swift:55
  ⏱ 4/147  NegateConditional              Loop.swift:9
```

When the schema does not build, the run says which mutants it drops before rebuilding:

```
  ⚠ Schema did not build: retrying without 2 mutants, to be built one by one
```

The readiness line names simulators on a simulator destination and workers elsewhere (`✓ 4 workers ready`). A run whose every mutant has a verdict in the cache prints `✓ Loaded 147 mutants from cache` instead of building.

Those mutants are not lost: each gets a build of its own, like an incompatible mutant, which is slower. Their build errors are in the `--keep-logs` output.

**Progress icons:**

| Icon | Meaning |
|---|---|
| `✓` | Killed — tests detected the mutation |
| `✗` | Survived — tests passed with the mutation active |
| `⚠` | Unviable — mutant did not compile |
| `⏱` | Timeout — test process exceeded the timeout |
| `–` | No coverage — the tests passed and none of them ran the mutated code |

### Text summary (always printed)

```
Results by file:
  Sources/Calculator.swift    score: 95.0%   killed: 19   survived: 1   timeout: 0   unviable: 0   no coverage: 0
  Sources/Validator.swift     score: 72.4%   killed: 21   survived: 8   timeout: 0   unviable: 0   no coverage: 0

Undetected mutants:
  Sources/Validator.swift:34:5   RelationalOperatorReplacement   survived
  Sources/Validator.swift:67:12  NegateConditional               survived

Overall mutation score: 85.3%
Detected: 122 (killed 122, timeout 0) / Undetected: 21 (survived 18, no coverage 3)
Killed: 122 / Survived: 18 / Timeouts: 0 / Unviable: 4 / NoCoverage: 3
Activation not measured: 1 mutant
Total duration: 5m 12s
```

Between the survived mutants and the score, a run that killed or timed out mutants whose code never ran lists them under `Integrity warnings` — the first 10, then `and N more — see the JSON report`; see [Mutation Results](MUTATION-RESULTS.md#integrity-warnings). `Activation not measured` counts the mutants that could not be instrumented, such as a mutation in an enum raw value or an attribute argument: for them a passing suite is reported as survived rather than no coverage.

**Mutation score formula:**

```
detected   = killed + timeouts
undetected = survived + noCoverage
score      = detected / (detected + undetected) × 100
```

A mutant killed by a crash counts as killed. Unviable mutants are excluded from both numerator and denominator. The `Detected` line shows both sides of the fraction, so a score earned by timeouts is visible. This is the formula the Stryker schema applies, so the JSON report scores the same in any Stryker-compatible viewer — see [Mutation score](MUTATION-RESULTS.md#mutation-score).

### Quiet mode (`--quiet`)

Suppresses all progress output. The text summary, the quality gate and the lines naming each report written are still printed at the end.

### JSON report (`--output`)

Stryker-compatible JSON report written to the specified path: per-file source content, per-mutant status and reason, the fingerprint and activation of each mutant, score thresholds, and the plan the run executed. Field by field in [Stryker Compatibility](STRYKER-COMPATIBILITY.md).

```bash
swift-mutation-testing --output mutation-report.json
```

### HTML report (`--html-output`)

A single self-contained HTML page: the score, the detection line and the totals, then a table per file with its score coloured (green at 100%, yellow from 50%, red below) and its survived mutants — line, column, operator and change — in a collapsible list. Every path and mutation text is HTML-escaped.

```bash
swift-mutation-testing --html-output mutation-report.html
```

### SonarQube report (`--sonar-output`)

SonarQube Generic Issue Import Format. Survived mutants are reported as `MAJOR CODE_SMELL` issues; no-coverage mutants as `MINOR`. Each issue has the engine `swift-mutation-testing`, the operator as its rule, the message `[<operator>] <change>`, and a `filePath` relative to the project with no leading slash (`Sources/Foo.swift`), so run the scanner with the project root as its base directory.

```bash
swift-mutation-testing --sonar-output sonar.json
```

### SARIF report (`--sarif-output`)

[SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html), the format GitHub code scanning reads. Each undetected mutant is one result, so it appears as an annotation on the line in a pull request and as an alert in the repository's Security tab.

- Only survived and no-coverage mutants are results, both at level `warning` — code scanning has no higher level for a quality finding, and `note` is hidden by default.
- There is one rule per operator present, with a description and a link to the [operator reference](#operator-identifiers). The message says whether a test ran the code (`No test failed when this code was changed.`) or none did (`No test executed this code.`), and `properties.mutationStatus` is `survived` or `noCoverage`.
- Locations are relative to the project, under the `%SRCROOT%` base, and columns are counted in UTF-16 code units, as SARIF expects.
- Each result carries the mutant's fingerprint as a partial fingerprint (`swiftMutationTesting/v1`), so code scanning keeps tracking the same alert across commits and closes it once the mutant is killed.
- Code scanning accepts at most 25,000 results per upload. Beyond that, the first 25,000 by file and line are written and a warning is printed.

```bash
swift-mutation-testing --sarif-output mutation-report.sarif
```

Upload it with `github/codeql-action/upload-sarif`, as in [the workflow below](#github-actions--annotations-job-summary-and-quality-gate).

### Markdown summary (`--markdown-output`)

A short summary for places that render Markdown, such as a GitHub Actions job summary or a GitLab merge request note: the score, the detection line and the totals, the quality gate's checks when a gate is configured, a table per file, and the first 20 undetected mutants.

```bash
swift-mutation-testing --markdown-output mutation-summary.md
cat mutation-summary.md >> "$GITHUB_STEP_SUMMARY"
```

### Caching

Results are cached at `<project>/.swift-mutation-testing-cache/results.json`, keyed by SHA256 of the source and test file contents, together with whether the mutated code ran. On subsequent runs, cached mutants skip the build and test cycle entirely.

The cache format is versioned. A cache written by an older version is discarded once, with a warning, and the run tests every mutant again; the next run writes a cache in the current format.

A cache belongs to the tests it was made with: the scheme, destination and project or workspace for Xcode, `--target` and `--testing-framework`. A run with any of them changed discards the cache, with a note, and tests every mutant again. To keep verdicts for two targets, give each its own CI job and cache. When some verdicts come from the cache, the summary says how many:

```
Verdicts from cache: 212 of 278
```

```
  ✓ Loaded 147 mutants from cache
```

Use `--no-cache` to force a full re-run:

```bash
swift-mutation-testing --no-cache
```

Besides `results.json`, written when a run ends, the cache keeps a journal, `journal.jsonl`, with every verdict appended the moment it is known. A run that is interrupted leaves its verdicts there, and the next run continues from them; see [Resuming an interrupted run](#resuming-an-interrupted-run).

---

## Suppressing Mutations

Two comment directives keep code out of the run. They are comments, so they need nothing declared and never affect your build.

```swift
// swift-mutation-testing:disable
func legacyParser(_ input: String) -> Result {
    // No mutant anywhere in this function
}

// swift-mutation-testing:disable — generated from the schema
struct GeneratedModel {
    // No mutant anywhere in this type
}

func checksum(_ data: Data) -> UInt32 {
    // swift-mutation-testing:disable-next-line
    var hash: UInt32 = 0x811c9dc5   // no mutant on this line
    ...
}
```

- `// swift-mutation-testing:disable`, in the comments right above a declaration, suppresses the whole declaration: functions, initializers, `deinit`, subscripts, classes, structs, enums, actors, extensions and properties. Attributes and doc comments may sit between it and the declaration.
- `// swift-mutation-testing:disable-next-line`, on a line of its own or at the end of one, suppresses every mutant on the line that follows.
- Anything after the directive, separated by a space, is a free-form reason. A comment that does not start with the exact directive — `disabled`, a `/* … */` block, the directive in the middle of a sentence — does nothing.

Suppressed mutations never appear in the report — they are filtered out before execution.

Earlier versions documented a `@SwiftMutationTestingDisabled` attribute. Swift rejects an attribute nothing declares, so it broke the build of any project that used it; the tool still honours it for projects that declared it themselves, but the comments are the way to suppress.

For whole files or directories — generated or vendored code — use `--exclude` instead.

### Excluding files

`--exclude` (repeatable) and the `exclude` key take two kinds of pattern:

- **A glob** — any pattern with `*`, `?` or `[` — is matched against the file's path relative to the project root, and also against the absolute path. `*` and `**` both cross directories:

  | Pattern | Leaves out |
  |---|---|
  | `**/Generated/**` | every file under any `Generated` directory, the root's included |
  | `Sources/Generated/**` | every file under `Sources/Generated` |
  | `*.pb.swift` | every file ending in `.pb.swift` |
  | `Sources/[AB]*/**` | every file under a `Sources` directory starting with `A` or `B` |

- **A fragment** — a pattern without those characters — leaves out every file whose path contains it: `/Generated/` leaves out any file under a `Generated` directory. Fragments are how `--exclude` always matched, so existing configurations keep working.

Some code is never mutated without any pattern or annotation:

- test code — any path containing `/Tests/`, `/Mocks/`, `/Stubs/`, `/Fakes/`, `/TestHelpers/`, `/TestSupport/`, `Tests.swift`, `Mock.swift` or `Spec.swift`;
- package manifests (`Package.swift`, `Package@swift-*.swift`) and `Snippets/`;
- build output and the tool's own directories: `.build/`, `DerivedData/`, `.swift-mutation-testing-derived-data/`, `.swift-mutation-testing-cache/`;
- the branches of an `#if` the macOS build leaves out — `#if os(Windows)`, `#if os(Linux)`, `#if canImport(Glibc)`, the `#else` of `#if canImport(Darwin)`.

A mutant in such a branch compiles to nothing and no test could reach it, so it would only inflate the survivor count. An `#if` on a module the tool does not know is kept whole.

---

## Quality Gate

By default a completed run exits with `0` whatever the score. The quality gate turns the result into a pass or fail for CI, and exits with `2` when it fails, after every report has been written.

| Policy | Flag / key | Fails when |
|---|---|---|
| Minimum score | `--min-score` / `min-score` | the score is below the minimum |
| Maximum drop | `--max-score-drop` / `max-score-drop` | the score is more than N points below the baseline's |
| No new survivors | `--max-new-survivors` / `max-new-survivors` | more than N undetected mutants (survived or no coverage) are not in the baseline |
| Integrity warnings | `--max-integrity-warnings` / `max-integrity-warnings` | more than N mutants were killed or timed out without the mutated code running |

Any combination can be set, on the command line or in `.swift-mutation-testing.yml`; the command line wins. Timeouts count as detected, as they do in the score.

An integrity warning is a verdict the test suite gave for a reason other than the mutation: a flaky or broken test, or a fault in the environment. See [Integrity warnings](MUTATION-RESULTS.md#integrity-warnings). Unset, they are listed and never fail the run; `--max-integrity-warnings 0` makes CI fail on the first one, so a flaky suite cannot keep inflating the score. This policy needs no baseline.

```
Quality gate: FAILED
  ✓ score 90.4% ≥ 85.0%
  ✓ score drop 0.7 pts ≤ 2.0 pts
  ✗ 2 new undetected mutants (max 0)
      Sources/Parser.swift:88   RelationalOperatorReplacement   < → <=
      Sources/Cache.swift:12    RemoveSideEffects               remove store()
  ℹ 3 mutants detected now that were undetected in the baseline
```

The checks come in the order of the table above, and at most 20 new undetected mutants are listed. The Markdown summary lists them too.

### Baselines

`--max-new-survivors 0` is what lets a project with existing survivors adopt the gate: the survivors already reviewed are recorded in a baseline, and CI fails on the first new one.

```bash
# Record the current state once, and commit the file
swift-mutation-testing --write-baseline .swift-mutation-testing-baseline.json

# In CI: fail on any survivor that is not in the baseline
swift-mutation-testing --baseline .swift-mutation-testing-baseline.json --max-new-survivors 0
```

Passing `--baseline` and `--write-baseline` together compares against the old baseline and then writes the new one, whatever the gate's outcome. Both paths are relative to the project.

The baseline is a JSON file meant to be committed and reviewed: the score, the scope of the run, and one entry per undetected mutant with its file, line, operator and change, sorted so its diff reads well in a pull request.

Mutants are matched by a **fingerprint**, not by position: a hash of the file path relative to the project, the declaration that contains the mutant (such as `Parser.parse(_:)`), the operator and the change. Adding lines above a mutant or editing another function leaves its fingerprint unchanged, and so does cloning the project to another directory. Renaming the function or the file, or editing the mutated expression itself, gives the mutant a new fingerprint, and it is reviewed as new.

A baseline records the scope it was made with — operators, `sources-path` and `exclude` patterns. When the current run's scope differs, the run stops with exit code `1` before any mutant runs, because comparing different scopes would report survivors that are merely out of scope as new, or hide real ones. A baseline written by a newer, incompatible version is refused the same way.

The fingerprint is also written to each mutant in the JSON report (`--output`).

---

## CI/CD Integration

An AI coding agent can run the tool and act on its report with the [Claude Code plugin](../README.md#using-with-ai-coding-agents), whose skill covers the same flow as this section.

### GitHub Actions — annotations, job summary and quality gate

A complete workflow: each undetected mutant becomes an annotation on its line in the pull request (SARIF through code scanning), the summary goes to the job summary, the reports are kept as an artifact, and a failed quality gate fails the job — after everything has been published.

```yaml
name: Mutation testing

on: pull_request

permissions:
  contents: read
  security-events: write   # needed to upload the SARIF report

jobs:
  mutation-testing:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v6

      - name: Install swift-mutation-testing
        run: |
          brew tap ericodx/homebrew-tools
          brew install swift-mutation-testing

      - name: Restore the result cache
        uses: actions/cache@v5
        with:
          path: .swift-mutation-testing-cache
          key: mutation-cache-${{ github.ref_name }}-${{ hashFiles('**/*.swift') }}
          restore-keys: mutation-cache-

      - name: Mutation testing
        id: mutation
        run: |
          set +e
          swift-mutation-testing --quiet \
            --sarif-output mutation-report.sarif \
            --markdown-output mutation-summary.md \
            --html-output mutation-report.html \
            --baseline .swift-mutation-testing-baseline.json --max-new-survivors 0
          echo "exit-code=$?" >> "$GITHUB_OUTPUT"

      - name: Annotate the pull request
        if: always() && hashFiles('mutation-report.sarif') != ''
        uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: mutation-report.sarif
          category: swift-mutation-testing

      - name: Write the job summary
        if: always() && hashFiles('mutation-summary.md') != ''
        run: cat mutation-summary.md >> "$GITHUB_STEP_SUMMARY"

      - name: Keep the HTML report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: mutation-report
          path: mutation-report.html
          if-no-files-found: ignore

      - name: Fail on errors and on a failed quality gate
        env:
          EXIT_CODE: ${{ steps.mutation.outputs.exit-code }}
        run: exit "$EXIT_CODE"
```

The mutation testing step records the exit code instead of failing, so the steps after it publish the reports first; the last step then fails the job with that code — `2` for a failed quality gate, `1` for an error.

- It needs a macOS runner.
- Uploading SARIF needs `security-events: write`. Pull requests from forks get a read-only token, so skip the upload step there.
- Drop the `--baseline` flags, or use `--min-score`, if the project has no baseline yet — see [Quality Gate](#quality-gate).

The shorter recipes below cover one piece each.

### GitHub Actions — run on every push

```yaml
- name: Mutation testing
  run: |
    swift-mutation-testing ${{ github.workspace }} \
      --scheme MyApp \
      --destination "platform=macOS" \
      --quiet
```

### GitHub Actions — generate HTML report as artifact

```yaml
- name: Mutation testing
  run: |
    swift-mutation-testing ${{ github.workspace }} \
      --scheme MyApp \
      --destination "platform=macOS" \
      --html-output mutation-report.html \
      --quiet

- name: Upload mutation report
  uses: actions/upload-artifact@v4
  with:
    name: mutation-report
    path: mutation-report.html
```

### GitHub Actions — SonarQube integration

```yaml
- name: Mutation testing
  run: |
    swift-mutation-testing ${{ github.workspace }} \
      --scheme MyApp \
      --destination "platform=macOS" \
      --sonar-output sonar.json \
      --quiet

- name: SonarQube scan
  uses: SonarSource/sonarqube-scan-action@v7
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
  with:
    args: >
      -Dsonar.externalIssuesReportPaths=sonar.json
```

### GitHub Actions — with config file

```yaml
- name: Mutation testing
  run: swift-mutation-testing ${{ github.workspace }} --quiet
```

When `.swift-mutation-testing.yml` is committed to the repository, no additional flags are needed.

### GitHub Actions — quality gate with a baseline

```yaml
- name: Mutation testing
  run: |
    swift-mutation-testing ${{ github.workspace }} \
      --baseline .swift-mutation-testing-baseline.json \
      --max-new-survivors 0 \
      --min-score 80 \
      --output mutation-report.json \
      --quiet
```

The step fails with exit code `2` when the gate fails. To accept the current survivors, run with `--write-baseline .swift-mutation-testing-baseline.json` locally and commit the file.

### Speed up CI with caching

Cache the `.swift-mutation-testing-cache` directory between runs to avoid re-testing unchanged mutants.

```yaml
- name: Cache mutation results
  uses: actions/cache@v4
  with:
    path: .swift-mutation-testing-cache
    key: mutation-cache-${{ hashFiles('Sources/**/*.swift', 'Tests/**/*.swift') }}
    restore-keys: mutation-cache-

- name: Mutation testing
  run: swift-mutation-testing ${{ github.workspace }} --quiet
```

### Limit scope in CI

Run only a subset of operators to keep CI fast, and run the deep set locally with `--operator-tier experimental`:

```yaml
- name: Mutation testing (fast)
  run: |
    swift-mutation-testing ${{ github.workspace }} \
      --operator NegateConditional \
      --operator SwapTernary \
      --quiet
```

---

## Exit Codes

A run that finds no mutant at all — a `--sources-path` with nothing mutable, everything excluded, no operator that applies — ends with `1` and says so. It reports no score: a 100% over zero mutants would be a perfect result for code that was never measured. A shard of a plan is the exception: splitting by file can leave one empty, and `merge` accounts for every mutant anyway.

| Code | Meaning |
|---|---|
| `0` | Success — the run completed, and the quality gate passed if one was configured |
| `1` | Error — usage error, build failure, unreadable or out-of-scope baseline, no mutant found in scope, or unexpected failure |
| `2` | Quality gate failed — the reports were written, but the result did not meet the policy |

Use the exit code in shell scripts:

```bash
swift-mutation-testing --quiet --min-score 80
case $? in
  0) echo "Mutation testing completed" ;;
  1) echo "Error — check scheme, destination, and project path" ; exit 1 ;;
  2) echo "Quality gate failed" ; exit 2 ;;
esac
```
