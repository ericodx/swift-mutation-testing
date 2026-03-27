# Mutation Results

This document explains every possible outcome for a mutant, what causes it, and what it means for your test suite. It also explains the distinction between **schematizable** and **incompatible** mutants — a concept that affects how the tool runs and how to interpret the progress output.

---

## Table of Contents

1. [Result types](#result-types)
   - [Killed](#killed-)
   - [Killed by crash](#killed-by-crash-)
   - [Survived](#survived-)
   - [Unviable](#unviable-)
   - [Timeout](#timeout-)
   - [No coverage](#no-coverage--)
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
Survived mutants:
  Sources/Validator.swift:34:5   RelationalOperatorReplacement
```

To address a survivor, add or strengthen a test that is sensitive to the original logic at that location.

---

### Unviable ⚠

**What it means:** the mutation produced code that does not compile. The mutant was never executed.

**What causes it:** not all token-level substitutions produce valid Swift. Examples:

- Swapping `+` for `-` in a string concatenation context produces a type error
- Removing a statement that is the sole expression in a single-expression function body can change the implicit return type
- Negating a condition that expects a non-optional `Bool` when the expression type is more complex

**What it tells you:** unviable mutants are a limitation of the mutation operators, not a gap in your tests. They do not count toward the mutation score. A high unviable rate for a particular operator in your codebase is a signal that the operator generates many syntactically valid but semantically invalid mutations in your context; this is expected and harmless.

**Effect on performance:** unviable mutants are discovered during the build step, not the test step, so they are cheap to discard.

---

### Timeout ⏱

**What it means:** the test process was still running when the per-mutant timeout expired. The process was killed and the mutant is treated as having survived for scoring purposes.

**What causes it:** the mutation introduced an infinite loop or a significantly longer execution path. Common sources:

- A relational operator change in a loop condition (`<` → `<=`, `>` → `<`) that causes the loop to run forever
- A negated conditional that sends execution down a much heavier path
- An arithmetic change that produces a much larger iteration count

**What it tells you:** a timeout almost certainly means the mutation altered the control flow in a way that a test would catch — it just ran out of time to do so. Timeouts are excluded from the mutation score denominator alongside kills, so they do not count against your score. If timeouts are frequent, consider raising `--timeout` or investigating whether your tests have sufficiently low execution time for the affected code paths.

---

### No coverage –

**What it means:** no test in the suite exercised the mutated code. The mutation was never active during any test execution.

**What causes it:** the mutated line is dead code for the test suite — no test triggers the code path that reaches it.

**What it tells you:** the code is untested by execution. This is worse than a survivor: a survivor at least means a test ran the code, just without asserting the right thing. No-coverage means the code is invisible to the test suite entirely. This is the highest-priority result to address: write a test that exercises the code path before worrying about what the mutation asserts.

No-coverage mutants are excluded from the mutation score denominator alongside kills.

---

## Mutation score

The score is a percentage of mutants that were detected by the test suite:

```
score = killed / (killed + survived + timeouts + noCoverage) × 100
```

| Status | Counted in denominator | Counted in numerator |
|---|---|---|
| Killed | yes | yes |
| Killed by crash | yes | yes |
| Survived | yes | no |
| Timeout | yes | no |
| No coverage | yes | no |
| Unviable | **no** | no |

Unviable mutants are excluded entirely — they are a property of the operators, not of the tests.

A score of 100% means every mutant that could be executed was detected by at least one test.

---

## Schematizable vs incompatible mutants

This is the most important internal distinction in how the tool operates. It directly affects execution speed and what you see in the progress output.

### Why the distinction exists

Running one full `xcodebuild build-for-testing` + `xcodebuild test-without-building` cycle per mutant would make mutation testing impractically slow for any real project. For a project with 200 mutants and a 20-second build, a naive approach would take over an hour just in build time.

The tool avoids this by **schematization**: rewriting source files to embed all mutations at once behind a runtime switch, building the project a single time, and then activating one mutant per test run by setting an environment variable. This reduces the total build cost to a single build regardless of the number of mutants.

```swift
// Original source
func isAdult(age: Int) -> Bool {
    return age >= 18
}

// Schematized source (embedded in the sandbox)
func isAdult(age: Int) -> Bool {
    switch __swiftMutationTestingID {
    case "swift-mutation-testing_0":
        return age > 18   // mutant 0: >= → >
    case "swift-mutation-testing_1":
        return age <= 18  // mutant 1: >= → <=
    default:
        return age >= 18  // original
    }
}
```

The global `__swiftMutationTestingID` reads from `ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"]`. Each test run injects a different mutant ID into that environment variable via the `.xctestrun` plist.

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

In all of these cases, the mutation site is not inside any executable scope that can host a `switch` statement. The tool falls back to applying the mutation directly to the source file, building the full project from scratch, and running `xcodebuild test` (not `test-without-building`).

### Performance implications

| | Schematizable | Incompatible |
|---|---|---|
| Builds required | 1 (shared) | 1 per mutant |
| Test command | `test-without-building` | `test` |
| Parallel execution | yes, N workers | sequential |
| Typical cost | seconds per mutant | full build + test per mutant |

A project with 10 incompatible mutants and a 20-second build will spend at least 200 extra seconds on incompatible execution alone, in addition to the shared build for schematizable mutants. The progress output calls this out explicitly:

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
