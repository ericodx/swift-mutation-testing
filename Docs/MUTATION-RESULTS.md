# Mutation Results

This document explains every possible outcome for a mutant, what causes it, and what it means for your test suite. It also explains the distinction between **schematizable** and **incompatible** mutants — a concept that affects how the tool runs and how to interpret the progress output. All concepts apply equally to both Xcode and SPM projects.

---

## Table of Contents

1. [Result types](#result-types)
   - [Killed](#killed-)
   - [Killed by crash](#killed-by-crash-)
   - [Survived](#survived-)
   - [Unviable](#unviable-)
   - [Timeout](#timeout-)
   - [No coverage](#no-coverage-)
   - [Integrity warnings](#integrity-warnings)
2. [Mutation score](#mutation-score)
3. [Schematizable vs incompatible mutants](#schematizable-vs-incompatible-mutants)
   - [Why the distinction exists](#why-the-distinction-exists)
   - [What makes a mutant incompatible](#what-makes-a-mutant-incompatible)
   - [Performance implications](#performance-implications)
   - [How to minimise incompatible mutants](#how-to-minimise-incompatible-mutants)

---

## Result types

### Killed ✓

**What it means:** the mutation was detected. At least one test failed when the mutant was active.

**What causes it:** a test assertion covered the exact logic that was mutated. The change in behaviour produced a different output, an exception, or a failed expectation that a test caught.

**What it tells you:** your tests are exercising this code path with a meaningful assertion. A high kill rate here is the goal.

**How it is measured:** for a Swift package, the tests named after the mutated file — `FooTests` for `Foo.swift`, when such a suite exists — run first, and the whole suite runs only if they let the mutant live. Either way the run is stopped as soon as one test fails, and that test is the one reported. Running the rest of the suite would change nothing about the verdict — killed is killed — so it is not run. Which test is reported first can differ between runs when the library runs tests in parallel; the verdict cannot.

**In the report:**

```
  ✓ 1/42  RelationalOperatorReplacement  Validator.swift:18
```

---

### Killed by crash ✓

**What it means:** the mutation caused the test process to crash before any test could fail normally. The result is treated as killed — the mutation did not survive.

**What causes it:** the mutant introduced code that crashes at runtime. Common sources:

- An arithmetic operator change that causes a division by zero
- A removed statement that skipped a required setup call, leading to a force-unwrap of `nil`
- A swapped ternary that returned a value incompatible with the assumption of the call site

**What it tells you:** a crash is a kill. The test suite caught the mutation — even if not through an explicit assertion. However, a crash may also indicate that certain input paths lack guard conditions. It is worth reviewing what triggered the crash.

---

### Survived ✗

**What it means:** the mutation was not detected. The test suite ran to completion with the mutant active, and all tests passed.

**What causes it:** one of the following:

- No test assertion covered the specific line or branch affected by the mutation
- Tests assert the wrong thing — they pass even when the behaviour changes
- The mutation affects code that is exercised by tests, but none of those tests are sensitive to the particular change

**What it tells you:** this is the most actionable result. A surviving mutant identifies a gap between what the code does and what the tests verify. The surviving location is shown with operator and position:

```
Undetected mutants:
  Sources/Validator.swift:34:5   RelationalOperatorReplacement   survived
```

To address a survivor, add or strengthen a test that is sensitive to the original logic at that location.

---

### Unviable ⚠

**What it means:** the mutation produced code that does not compile. The mutant was never executed.

**What causes it:** not all token-level substitutions produce valid Swift. Examples:

- Swapping `+` for `-` in a string concatenation context produces a type error
- Removing a statement that is the sole expression in a single-expression function body can change the implicit return type
- Negating a condition that expects a non-optional `Bool` when the expression type is more complex

**What it tells you:** unviable mutants are a limitation of the mutation operators, not a gap in your tests. They do not count toward the mutation score, and their activation is not measured, since they never ran. A high unviable rate for a particular operator in your codebase is a signal that the operator generates many syntactically valid but semantically invalid mutations in your context; this is expected and harmless.

**Effect on performance:** unviable mutants are discovered during the build step, not the test step, so they are cheap to discard.

---

### Timeout ⏱

**What it means:** the test process was still running when the per-mutant timeout expired — and it was still running when the mutant was run again on its own. A mutant that times out while the other workers are busy is not given this verdict straight away. The parallel pass allows twice the configured `--timeout`, and once it is over every mutant still unsettled is run once more with at most a quarter of the workers, under the configured `--timeout`; only that second timeout is reported. That second run has no contention to blame, so the verdict describes the mutation rather than the machine. The process was killed and the mutant counts as detected in the score.

**What causes it:** the mutation introduced an infinite loop or a significantly longer execution path. Common sources:

- A relational operator change in a loop condition (`<` → `<=`, `>` → `<`) that causes the loop to run forever
- A negated conditional that sends execution down a much heavier path
- An arithmetic change that produces a much larger iteration count

**What it tells you:** a timeout means the mutation changed the control flow enough that the suite could no longer finish — and the isolated rerun rules out a busy machine as the cause. It is treated as **detected**, like a kill: the tests did not let the mutant pass. Stryker, Muter and PIT count timeouts the same way, which keeps our score identical to the one any Stryker-compatible tool computes from the JSON report. Timeouts are still reported on their own line — `Detected: N (killed K, timeout T)` — so a high score earned by timeouts is visible. If timeouts are frequent, consider raising `--timeout` or investigating whether your tests have sufficiently low execution time for the affected code paths.

Mutants that loop forever are largely prevented at discovery rather than timing out here — see **Infinite-loop prevention** in the [mutation operators reference](CodeBase/04-mutation-operators.md).

---

### No coverage –

**What it means:** no test executed the mutated code. The tests all passed with the mutant active, and the mutant's own branch of the schema never ran.

**How it is measured:** every `case` of the schema begins by recording that it ran — a marker file, named after the mutant, that the test process creates the first time the mutated code executes. After the run, a passing suite whose marker was never written is reported as no coverage instead of survived. The marker is checked after the targeted run and after the full run, and either one counts. Mutants that cannot be schematized (see below) have no `case`, so their mutated expression is wrapped instead, in a call that records the same marker and returns the value unchanged; a removed statement is replaced by the recording call. A few places cannot take a call, such as enum raw values, attribute arguments, macro arguments and `#if` conditions, and a mutant whose instrumented copy does not compile is built again without the call. Those mutants are not measured: a passing suite is reported as survived, and the summary counts them under "Activation not measured".

**What causes it:** the mutated line is dead code for the test suite — no test triggers the code path that reaches it.

**What it tells you:** the code is untested by execution. This is worse than a survivor: a survivor at least means a test ran the code, just without asserting the right thing. No-coverage means the code is invisible to the test suite entirely. This is the highest-priority result to address: write a test that exercises the code path before worrying about what the mutation asserts.

No-coverage mutants count in the score denominator and not in the numerator, like survivors: the code was mutated and nothing noticed.

---

### Integrity warnings

A verdict is only worth something if the mutated code ran. The same marker that tells a survivor from no coverage also exposes the opposite case: a mutant that was **killed** — or timed out — although its code never ran. The test that failed did not fail because of the mutation; it is flaky, broken for another reason, or the environment is at fault.

A mutant killed without activation is run once more, alone, after every other mutant. A flaky test usually passes the second time, and the mutant is then judged by that run. A kill that repeats without activation is systematic: it keeps its status, and the run lists it, together with timeouts whose code never ran:

```
Integrity warnings (2): killed or timed out without the mutated code running
  Sources/Parser.swift:88:12   RelationalOperatorReplacement   killed without activation
  Sources/Cache.swift:12:5     RemoveSideEffects               timed out without activation
```

The JSON report carries the same fact as `statusReason`: `killed without activation`, `crash without activation` or `timed out without activation`. Treat a warning as a test suite problem, not a mutant to fix. To make CI fail on warnings, set `--max-integrity-warnings 0`; see [Quality Gate](USAGE.MD#quality-gate).

Two situations stop the run altogether, with exit code `1`, because no verdict could be trusted:

- **A mutant that did not reach the sandbox.** Before the build, every schematized file is checked to differ from its original, to declare its support, and to hold a `case` for every schematizable mutant; every incompatible mutant is checked to have content that differs from the original. A mutant the check cannot find is named in the error. This catches a generator that silently dropped a mutation.
- **Kills without any activation.** When mutants were killed but no mutant's code was ever seen running, either the marker cannot be written in this environment or the suite fails on its own. Reporting those kills would produce a flattering score built on nothing.

---

## Mutation score

The score is the percentage of mutants the test suite detected:

```
detected   = killed + killed by crash + timeouts
undetected = survived + noCoverage
score      = detected / (detected + undetected) × 100
```

| Status | Side | Counted in denominator | Counted in numerator |
|---|---|---|---|
| Killed | detected | yes | yes |
| Killed by crash | detected | yes | yes |
| Timeout | detected | yes | yes |
| Survived | undetected | yes | no |
| No coverage | undetected | yes | no |
| Unviable | — | **no** | no |

Unviable mutants are excluded entirely — they are a property of the operators, not of the tests. When no mutant is detected or undetected — every one unviable — the score is 100%. A run that discovers no mutant at all reports no score: it ends with exit code 1, since nothing was measured.

The console and the HTML report print both sides under the score:

```
Overall mutation score: 90.0%
Detected: 9 (killed 8, timeout 1) / Undetected: 1 (survived 1, no coverage 0)
```

This is the formula the [Stryker report schema](STRYKER-COMPATIBILITY.md) applies, so the score in the console, in the HTML report and in any Stryker-compatible viewer of the JSON report is the same number.

A score of 100% means every mutant that could be executed was detected by at least one test or by the suite failing to finish.

### The number on the README badge

The badge is this repository's own score on the `default` tier, taken from the self-run of the operator campaign — the entry `"."` of `Scripts/operator-campaign/corpus.json`, with its arguments: `Fixtures/` (test data), `Scripts/` (the campaign tooling, which no test runs) and the two sandbox files whose mutants would delete the run's own sandboxes are left out, and the timeout is 300 s so that a surviving mutant's full suite fits. The campaign runs every operator, so the badge's number is the score recomputed over the mutants of the `default` tier's operators in that report; `Docs/OPERATORS.md` has the full result and the date. It is a record run, not a push-time number: it moves when the campaign is rerun. The last self-run, on 2026-10-08, gives 99.8% on the `default` tier (99.2% over every operator).

---

## Schematizable vs incompatible mutants

This is the most important internal distinction in how the tool operates. It directly affects execution speed and what you see in the progress output.

### Why the distinction exists

Running one full build + test cycle per mutant would make mutation testing impractically slow for any real project. For a project with 200 mutants and a 20-second build, a naive approach would take over an hour just in build time.

The tool avoids this by **schematization**: rewriting source files to embed all mutations at once behind a runtime switch, building the project a single time, and then activating one mutant per test run by setting an environment variable. This reduces the total build cost to a single build regardless of the number of mutants. This works for both Xcode projects (`xcodebuild build-for-testing`, then `test-without-building`) and SPM packages (`swift build --build-tests`, then the compiled test bundles run directly — `xcrun xctest` for XCTest, the toolchain's `swiftpm-testing-helper` for Swift Testing — with `swift test --skip-build` when the build left no bundle).

```swift
// Original source
func isAdult(age: Int) -> Bool {
    return age >= 18
}

// Schematized source (embedded in the sandbox)
func isAdult(age: Int) -> Bool {
    switch __swiftMutationTestingID_<hash> {
    case "swift-mutation-testing_0":
        return age > 18   // mutant 0: >= → >
    case "swift-mutation-testing_1":
        return age <= 18  // mutant 1: >= → <=
    default:
        return age >= 18  // original
    }
}
```

Each schematized file declares its own `__swiftMutationTestingID_<hash>` — the hash names the file — which reads `ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"]` once. Each test run injects a different mutant ID into that environment variable — via the `.xctestrun` plist for Xcode projects, or via the process environment for SPM packages.

### What makes a mutant incompatible

Schematization requires the mutation to fall inside a **function body** — a `func`, `init`, `deinit`, or property accessor. A `switch` statement can only appear inside an executable scope.

Mutations that land outside function bodies cannot be embedded in a switch and require a separate build per mutant. These are **incompatible mutants**. Common examples:

**Default parameter values**

```swift
func greet(name: String = "World") -> String {  // ← mutation here: outside a body
    return "Hello, \(name)"
}
```

**Stored property initialisers**

```swift
struct Config {
    var timeout: Double = 60.0  // ← mutation here: outside a body
    var retryCount: Int = 3     // ← mutation here: outside a body
}
```

**Global variable initialisers**

```swift
let defaultConcurrency = max(1, ProcessInfo.activeProcessorCount - 1)  // ← outside a body
```

**Enum raw values**

```swift
enum ExitCode: Int32 {
    case success = 0  // ← outside a body
    case error   = 1  // ← outside a body
}
```

In all of these cases, the mutation site is not inside any executable scope that can host a `switch` statement. The tool falls back to applying the mutation directly to the source file and running a build + test cycle per mutant. Each worker gets a sandbox of its own, built once; for every mutant it writes the mutated file, rebuilds, runs the tests, and restores the original.

### Performance implications

| | Schematizable | Incompatible |
|---|---|---|
| Builds required | 1 (shared) | 1 per worker, then 1 incremental rebuild per mutant |
| Test command | `test-without-building` (Xcode) / the test bundles (SPM) | build + test per mutant |
| Parallel execution | yes, `--concurrency` workers | a quarter of the workers, at least 1 |
| Typical cost | seconds per mutant | an incremental build + test per mutant |

Incompatible mutants are the expensive ones: each needs its own rebuild before its tests can run. The rebuild is incremental — the sandbox is built once and only the mutated file is recompiled after that — and the mutants are spread over a quarter of the workers, but a project with 10 incompatible mutants still pays roughly 10 rebuilds plus 10 test runs on top of the shared build for schematizable mutants. The progress output calls this out explicitly:

```
  ✓ Discovery: 154 mutants (143 schematizable, 11 incompatible) in 2.3s
```

### How to minimise incompatible mutants

Move logic from declaration sites into function bodies:

**Before — incompatible**

```swift
struct NetworkClient {
    var timeout: Double = 60.0
    var maxRetries: Int = 3
}
```

**After — schematizable**

```swift
struct NetworkClient {
    var timeout: Double
    var maxRetries: Int

    init(timeout: Double = 60.0, maxRetries: Int = 3) {
        self.timeout = timeout        // mutations here are inside a function body
        self.maxRetries = maxRetries
    }
}
```

**Before — incompatible**

```swift
func connect(host: String, port: Int = 443) { ... }
```

**After — schematizable**

```swift
func connect(host: String, port: Int) { ... }

func connect(host: String) {
    connect(host: host, port: 443)  // mutation here is inside a body
}
```

In practice, incompatible mutants are a small fraction of the total and their results are as meaningful as schematizable ones. The distinction matters for planning — if you notice a large incompatible count, the strategies above can reduce build time significantly.
