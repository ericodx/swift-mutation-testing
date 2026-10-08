---
name: swift-mutation-testing
description: Run mutation testing on a Swift package or Xcode project with swift-mutation-testing, read the report, and write the tests that kill surviving mutants. Use when the user asks how good their Swift tests really are, whether the tests would catch a bug, where assertions are weak or missing, what the mutation score is, or asks to run swift-mutation-testing.
---

# Swift mutation testing

`swift-mutation-testing` changes the code under test in small ways — `<` to `<=`, `true` to `false`, a call removed — and runs the test suite once per change. Each change is a *mutant*. A mutant the tests catch is **killed**. A mutant no test notices **survived**: the code can be wrong in that exact way and the suite still passes. Coverage says a line ran; a survivor says nothing checked what it did.

The project is never modified. Every build and test run happens in a copy under `$TMPDIR/swift-mutation-testing/`.

Reference, when a detail here is not enough: [Usage](https://github.com/ericodx/swift-mutation-testing/blob/main/Docs/USAGE.MD) and [Mutation results](https://github.com/ericodx/swift-mutation-testing/blob/main/Docs/MUTATION-RESULTS.md).

## 1. Preconditions

1. **The tool is installed.** Run `swift-mutation-testing --version`. If it is missing, ask the user before installing it with `brew tap ericodx/homebrew-tools && brew install swift-mutation-testing`. It needs macOS 15+ and Swift 6.2+.
2. **The suite passes without mutations.** A suite that already fails kills every mutant, and the score means nothing.
   - Swift package: the tool checks this itself and stops with the failing tests named. Fix those first.
   - Xcode project: the tool does **not** check it. Run the tests yourself first (`xcodebuild test` with the same scheme and destination) and stop if they fail.
3. **The run is not in a hurry.** The suite runs once per mutant. On a package with a two-second suite and 300 mutants, expect minutes. On an app, expect much longer. Tell the user what you are about to start, and narrow the scope (step 2) when the project is large.

## 2. First run

If the project has no `.swift-mutation-testing.yml`, generate one:

```bash
swift-mutation-testing init <project-path>
```

`init` detects the project type, the scheme and destination (Xcode), the workspace or project to build, the test target and the testing library. Read the generated file and check the scheme, the destination and `test-target` before running. Skip `init` when the file already exists: it holds the user's settings.

**Xcode workspaces.** An app with CocoaPods, several projects or local packages is a workspace, and it is built as one. The tool takes the single `.xcworkspace` (else the single `.xcodeproj`) at the project root. When there are two, or when the only ones sit in a subdirectory, it refuses to guess: the run stops naming the candidates, and `init` writes them commented out. Then ask the user which one the app is built from, and pass it with `--workspace App.xcworkspace` or `--project App.xcodeproj` (relative to the project root), or set the `workspace` / `project` key. Keep `Pods/` out of scope with `--exclude /Pods/` when it sits under the sources path. A workspace that references projects outside the project root cannot be run from that root; run from a directory that contains them all.

Always write the JSON report, because the text summary is for people and the JSON is what you read:

```bash
swift-mutation-testing <project-path> --output mutation-report.json
```

A Swift package needs no scheme or destination. An Xcode project needs both, in the file or as `--scheme` and `--destination "platform=macOS"` (or a simulator destination).

Narrowing the scope:

| Goal | How |
|---|---|
| One module, folder or file | `--sources-path Sources/MyModule`, or a single `.swift` file to re-check it after adding a test |
| Skip generated or vendored code | `--exclude "**/Generated/**"` (a glob, relative to the project root) or `--exclude /Generated/` (a fragment of the path); repeatable |
| A few operators | `--operator RelationalOperatorReplacement --operator NegateConditional` |
| Every operator, including the experimental ones | `--operator-tier experimental`; the default tier is `default` — `LogicalOperatorReplacement`, `NegateConditional`, `SwapTernary` — see `Docs/OPERATORS.md` |
| One test target | `--target MyPackageTests` |

Test files (`Tests/`, `Mocks/`, `Stubs/`, `Fakes/`, `TestHelpers/`, `TestSupport/`, `*Tests.swift`, `*Mock.swift`, `*Spec.swift`), build output (`.build/`, `DerivedData/`), package manifests (`Package.swift`, `Package@swift-*.swift`) and `Snippets/` are never mutated, and neither are the branches of an `#if` the macOS build leaves out (`#if os(Windows)`, `#if canImport(Glibc)`).

A second run on unchanged code is fast: verdicts are cached in `.swift-mutation-testing-cache/`, keyed by file contents. Editing a source file re-tests that file's mutants; editing a test file re-tests the mutants that survived, and the killed ones whose killing test lives in that file. Use `--no-cache` only to rule out the cache when a result looks wrong.

## 3. Reading the result

The text summary ends with:

```
Overall mutation score: 85.3%
Detected: 122 (killed 122, timeout 0) / Undetected: 21 (survived 21, no coverage 0)
Killed: 122 / Survived: 21 / Timeouts: 0 / Unviable: 4 / NoCoverage: 0
```

```
detected   = killed + timeouts
undetected = survived + noCoverage
score      = detected / (detected + undetected) × 100
```

Each mutant in the JSON report (`files["/Sources/Foo.swift"].mutants[]`) carries `mutatorName`, `originalText`, `replacement`, `location.start.line` and `.column` (both 1-based), `status`, `killedBy` when a test killed it, and a `fingerprint` that identifies the mutant across runs. Its `status` is one of:

| `status` | Meaning | Action |
|---|---|---|
| `Killed` | A test failed with the mutant active. `statusReason: "crash"` means the process crashed instead | None |
| `Timeout` | The suite never finished, even when rerun with fewer workers. Counts as detected | None, unless there are many: check `--timeout` |
| `Survived` | The suite passed with the mutant active | **Write a test** (step 5) |
| `NoCoverage` | The suite passed and the mutated code never ran — measured, not guessed: every mutant records when its code executes | Write a test that reaches the code first |
| `CompileError` | The mutant did not compile | None. It is a property of the operator, not of the tests, and it is outside the score |

A 100% score means every mutant that compiled was detected. It does not mean the code is right.

Two lines can follow the summary. `Integrity warnings (N)` lists mutants that were **killed or timed out without their code running**: the test that failed did not fail because of the mutation, so treat those as flaky or broken tests, not as mutants to fix. A kill without activation was already run a second time, alone, and failed again, so it is not a one-off flake; in the JSON they carry `statusReason: "killed without activation"` (or `crash …`, `timed out …`). `Activation not measured: N mutants` means those mutants could not be instrumented, so for them a passing suite reads `survived` even if the code never ran.

The run stops with exit code `1`, before reporting anything, when a mutant did not reach the build (`… not applied to the sandbox`) or when mutants were killed but no mutant's code was ever seen running. Both mean the verdicts could not be trusted; the message says which. Report the error to the user rather than working around it.

## 4. Prioritizing

Work through the undetected mutants in this order:

1. **`NoCoverage` before `Survived`.** A whole path is untested, which is worse than a weak assertion.
2. **Group by file, then by function.** Several survivors in one function usually share one missing test: a boundary never checked, a branch never taken, a return value never asserted.
3. **One operator surviving repeatedly in one function is one cause.** `RelationalOperatorReplacement` surviving on `>=` and `>` at the same line means the boundary value is never tested.
4. **Business logic before glue.** A survivor in a pricing rule matters more than one in a log message.

What each operator's survivor usually means:

| Operator | A survivor usually means |
|---|---|
| `RelationalOperatorReplacement` | The boundary value (`x == limit`) is not tested |
| `BooleanLiteralReplacement` | A flag's effect is not asserted |
| `LogicalOperatorReplacement` | Only cases where both sides agree are tested |
| `ArithmeticOperatorReplacement` | The computed value is not asserted exactly |
| `NegateConditional` | Only one side of the branch is tested |
| `SwapTernary` | Both results of the ternary are never compared |
| `RemoveSideEffects` | The call's effect (state change, callback, write) is not verified |

## 5. Killing a survivor

1. Open the file at `location.start.line`. Apply `originalText` → `replacement` in your head and say what behavior changes.
2. Find the existing tests for that code, and use the library they use (XCTest or Swift Testing).
3. Write a test that **fails with the mutation and passes without it**: an input that reaches the line, and an assertion on the exact value or effect that the mutation changes.
4. Run the normal test suite. The new test must pass on the unmutated code.
5. Rerun the tool on the directory that holds the file (`--sources-path`), with `--output`. Confirm the mutant now reports `Killed` and `killedBy` names your test.

Never make a survivor go away by changing production code to avoid the mutation, by weakening an operator, or by excluding the file. The survivor is information about the tests, and the fix belongs in the tests.

When a test fails in a way you do not understand, rerun with `--keep-logs <dir>`: each mutant's full test output lands in `<dir>/<mutant-id>.log`, with an `activated:` line in the header saying whether the mutated code ran during that test run.

To look at one verdict closely, `swift-mutation-testing reproduce <id-or-fingerprint>` runs that mutant alone with the whole suite and no stop at the first failure, keeps its sandbox, and prints the sandbox path, the line before and after the mutation, the complete test output and the verdict with its reason. Read the output before writing a test.

## 6. Mutants that cannot be killed

Some survivors are **equivalent**: the mutation does not change observable behavior (for example `a > b ? a : b` → `a >= b ? a : b`: when `a == b` both return the same value). No test can kill them. Tell the user which ones you believe are equivalent and why, rather than writing a meaningless test.

To keep code out of the run, use `--exclude` (or `exclude:` in the config file) for generated and vendored files. For one declaration or one line, write the comment `// swift-mutation-testing:disable` above the declaration, or `// swift-mutation-testing:disable-next-line` above the line, with the reason after it (`// swift-mutation-testing:disable — equivalent: reserveCapacity is a hint`). Suppress only with the user's agreement and never to make a survivor disappear. Do not use the old `@SwiftMutationTestingDisabled` attribute: Swift rejects it unless the project declares it.

## 7. Continuous integration

- **On GitHub**, the usage guide has a complete workflow ("GitHub Actions — annotations, job summary and quality gate"): it installs the tool with Homebrew on a macOS runner, runs it with `--sarif-output` and `--markdown-output`, uploads the SARIF with `github/codeql-action/upload-sarif` so each survivor becomes an annotation on its line in the pull request, writes the Markdown to the job summary, and only then fails the job with the tool's exit code. Uploading SARIF needs `permissions: security-events: write`. Adapt that workflow rather than writing one from scratch.
- Commit `.swift-mutation-testing.yml` so CI runs with no extra flags: `swift-mutation-testing --quiet --output mutation-report.json`. `--sarif-output` writes a SARIF 2.1.0 report and `--markdown-output` a Markdown summary for CI systems that render it.
- Cache `.swift-mutation-testing-cache/` between runs (`actions/cache`), keyed on the Swift sources and tests. The cache also holds a journal of verdicts, so a run that was cut short continues on the next run.
- **A long run can be split across machines.** `swift-mutation-testing plan --output plan.json` writes the mutants without building; `run --plan plan.json --shard i/n` runs one slice on each machine; `merge result-*.json --plan plan.json --output …` joins the slices into one report and runs the gate over it. The usage guide has a GitHub Actions matrix for this under "Plans". A shard must check out the commit the plan was made from, or it refuses to run.
- Exit codes: `0` the run completed (and the quality gate passed, if set); `1` an error (bad arguments, a build that failed, a suite that fails without mutations, an unusable baseline); `2` the quality gate failed. On `2` the reports were still written.
- **Quality gate.** Suggest one when the user wants CI to fail on weak tests:
  - `--min-score 80` (or `min-score: 80` in the config file): fail below a score.
  - For a project that already has survivors, record them once and fail only on new ones:
    ```bash
    swift-mutation-testing --write-baseline .swift-mutation-testing-baseline.json   # commit this file
    swift-mutation-testing --baseline .swift-mutation-testing-baseline.json --max-new-survivors 0
    ```
  - `--max-score-drop 2` with `--baseline`: fail when the score falls more than 2 points below the baseline's.
  - `--max-integrity-warnings 0`: fail when any mutant was killed or timed out without its code running, so a flaky suite cannot inflate the score. Needs no baseline.
  - Mutants are matched by fingerprint (file, enclosing declaration, operator, change), so edits elsewhere do not make old survivors look new. Renaming the function or editing the mutated expression does.
  - After killing survivors, write the baseline again so the fixed ones leave it. Never write a new baseline just to make a failing gate pass without telling the user which survivors it accepts.
- `--sonar-output` writes survivors as SonarQube external issues; `--html-output` writes a report for people.

## 8. Pitfalls

- **Do not compare scores across scopes.** A run with `--operator`, `--sources-path` or `--exclude` scores a different set of mutants than a full run.
- **A baseline only compares with the same scope.** A run whose operators, `--sources-path` or `--exclude` differ from the baseline's stops with exit code `1` and lists the differences. Run with the baseline's scope, or write a new baseline on purpose.
- **One run per project at a time.** Two runs on the same project write the same cache.
- **Xcode needs a destination that exists.** An iOS simulator destination must name an installed simulator; for code that runs on macOS, `platform=macOS` is faster and needs no simulator.
- **Timeouts cost time.** Each one waits for twice `--timeout` in the parallel pass (`--timeout` is 30 s for packages, 120 s for Xcode by default), then is rerun once with fewer workers, under `--timeout`, before it is reported.
- **Do not leave the reports in the repository** unless the user asks: add `mutation-report.json` and `.swift-mutation-testing-cache/` to `.gitignore`.
