# Operators

Every operator has a **tier**, and the tier comes from measured data, not from opinion. A run takes the operators up to a tier (`--operator-tier`, or `operator-tier` in the file; see [USAGE.MD](USAGE.MD#operator-tiers)): `conservative` is the smallest set, `default` is what runs when nothing is said, `experimental` holds every operator.

## Tiers

| Tier | Every criterion must hold |
|---|---|
| `conservative` | median kill rate ≥ 70%, unviable ≤ 5%, equivalent ≤ 10% |
| `default` | median kill rate ≥ 40%, unviable ≤ 15%, equivalent ≤ 25% |
| `experimental` | the rest, or insufficient data: fewer than 3 projects with at least 10 mutants of the operator |

The limits were proposed before any data existed. A campaign may show they need to move; every change is recorded under [Decisions](#decisions) with its reason. The first campaign moved one: a project qualifies with 10 mutants of an operator, not 30.

## Metrics

Every number comes from the tool's own JSON reports, one per project, read by `.github/scripts/operator-campaign/campaign.swift aggregate`; the per-(operator, project) rows are in [`operators/results.csv`](operators/results.csv). A *cell* below is one operator in one project.

| Metric | Definition |
|---|---|
| Generated | mutants the operator produced in the project, every status included |
| Detected / undetected | detected = killed + timeout; undetected = survived + no coverage, the score's own split |
| Kill rate | detected ÷ (detected + undetected), per cell; unviable mutants are outside both sides, as in the score |
| Median kill rate | the median of the kill rates of the *qualified* cells of the operator, one value per project, so a project with 600 mutants weighs the same as one with 12 |
| Unviable | unviable ÷ generated over all the operator's cells, qualified or not: a mutant that does not compile is the operator's doing, whatever the project |
| No coverage | no coverage ÷ generated, per cell; reported, not a criterion |
| Cost per mutant | the mean `duration` of the operator's mutants, the time their tests took, cached results excluded; it says what a run spends on the operator, and it depends on the suite and on the stop rule, so compare operators within a project rather than projects with each other |
| Equivalent (reviewed) | equivalent ÷ (equivalent + not equivalent) over the operator's hand-reviewed survivors, every project together; the count in parentheses is the reviews behind the share. A review marked *not measurable* counts on neither side |
| Qualified projects | a cell qualifies when it holds at least 10 mutants of the operator (`--min-mutants`); an operator needs 3 qualified cells to be judged at all, else it is `experimental` for insufficient data |

The tier then follows the [criteria](#tiers) in that order: fewer than 3 qualified projects, or a median kill rate under 40%, or more than 15% unviable, is `experimental`; otherwise a median of at least 70% with at most 5% unviable and 10% equivalent is `conservative`; otherwise at most 25% equivalent is `default`; the rest is `experimental`. An operator with the kill rates to qualify but no reviewed survivor yet is *pending review*.

## Current tiers

Assigned on 2026-10-05 from the second run of the record campaign, by the criteria above:

| Tier | Operators | What it buys |
|---|---|---|
| `conservative` | `LogicalOperatorReplacement`, `NegateConditional`, `SwapTernary` | median kill rate ≥ 81%, no unviable mutant to speak of, fewer than one survivor in ten equivalent |
| `default` | the same three | the everyday run and CI. `BooleanLiteralReplacement` qualified on the first run's 33 reviews (12% equivalent) and misses the 25% limit on the second run's 61 (27.9%): `atomically:`, `withIntermediateDirectories:` and `isDirectory:` flags whose other value nothing can observe. So the everyday run is the conservative set, until a campaign says otherwise |
| `experimental` | `BooleanLiteralReplacement`, `RelationalOperatorReplacement`, `RemoveSideEffects`, `ArithmeticOperatorReplacement` | the deep run, `--operator-tier experimental`, for when someone will read the survivors: kill rates from 69% to 89%, but between one survivor in four (`Boolean`, `RemoveSideEffects`, `Arithmetic`) and one in three (`Relational`) is equivalent, and `Relational` alone is half of all mutants |

A run with no `operator-tier` takes `default`. Before the campaign every operator ran by default; a score computed then and one computed now are not comparable, and `Docs/USAGE.MD` says so.

## Results of the record campaign

Run on 2026-10-04 and 05 (this repository last), with `swift-mutation-testing 0.0.0-dev [arm64-macos26]` built from the commit of this document, swift-driver version: 1.168.6 Apple Swift version 6.4, on Apple M4 Max, Version 26.6.2 (Build 25G83). Every number below comes from [`operators/results.csv`](operators/results.csv) and [`operators/equivalence.csv`](operators/equivalence.csv), written by `aggregate` and `sample` over the reports of that run.

### Operators

| Operator | Tier by the criteria | Projects (≥ 10 mutants) | Median kill rate | Unviable | Equivalent (reviewed) | Cost per mutant |
|---|---|---|---|---|---|---|
| `ArithmeticOperatorReplacement` | experimental | 4 of 5 | 88.9% | 12.1% | 27.3% (33) | 2969 ms |
| `BooleanLiteralReplacement` | experimental | 5 of 5 | 73.6% | 11.5% | 27.9% (61) | 11050 ms |
| `LogicalOperatorReplacement` | conservative | 4 of 5 | 81.0% | 0.0% | 9.1% (33) | 9232 ms |
| `NegateConditional` | conservative | 5 of 5 | 96.2% | 0.2% | 8.6% (35) | 2593 ms |
| `RelationalOperatorReplacement` | experimental | 5 of 5 | 82.7% | 7.4% | 32.6% (86) | 5669 ms |
| `RemoveSideEffects` | experimental | 5 of 5 | 69.3% | 1.9% | 27.8% (79) | 19619 ms |
| `SwapTernary` | conservative | 4 of 5 | 94.9% | 0.0% | 7.1% (14) | 6006 ms |

The tier column is what the criteria give for the numbers in the row; the tiers in force are in [Current tiers](#current-tiers) above, with the decisions that led there.

### Projects

| Project | Commit | Mutants | Score | Killed / survived / timeouts / no coverage / unviable | Integrity warnings | Wall time |
|---|---|---|---|---|---|---|
| swift-algorithms | `87e50f483c` | 1112 | 87.4% | 857 / 121 / 30 / 7 / 97 | 0 | 16 min |
| swift-argument-parser | `6a52f32511` | 822 | 65.3% | 474 / 221 / 3 / 33 / 91 | 0 | 18 min |
| swift-log | `9c6fb14227` | 209 | 77.8% | 156 / 36 / 2 / 9 / 6 | 1 | 1 min |
| swift-cpd | `7c4e7bb5e3` | 987 | 92.2% | 880 / 76 / 21 / 0 / 10 | 7 | 15 min |
| swift-mutation-testing | `533a4be6e4` | 1275 | 80.9% | 1001 / 239 / 12 / 0 / 23 | 3 | 146 min |

`swift-cpd` runs at the `main` commit that fixed its test helper (ericodx/swift-cpd#39: the executable was looked up through `Bundle.allBundles`, which finds no `.xctest` under `swiftpm-testing-helper`, so the suite failed before any mutation); no release carries the fix yet. Its seven integrity warnings are crashes and failures of its own suite in runs where the mutant never ran — a suite that is not fully deterministic under fifteen parallel runs; they are listed in its report and count as kills in its score. This repository's run is the one that matters most to the tool itself: 1275 mutants at 80.9% over every operator, with 3 integrity warnings, measured after the fixes described under [Decisions](#decisions); over the `default` tier's three operators the same report scores 93.4%. The self-run was repeated on its own on 2026-10-08, after the tests added since; that run, and the score on the README badge, are under [Decisions](#decisions). There is no Xcode app in this campaign.

### Review of survivors

Up to 20 survivors per (operator, project), drawn with seed 20261001, each read in its source and classified:

| Operator | Sampled | Equivalent | Not equivalent | Not measurable | Equivalent share |
|---|---|---|---|---|---|
| `ArithmeticOperatorReplacement` | 33 | 9 | 24 | 0 | 27.3% |
| `BooleanLiteralReplacement` | 61 | 17 | 44 | 0 | 27.9% |
| `LogicalOperatorReplacement` | 33 | 3 | 30 | 0 | 9.1% |
| `NegateConditional` | 37 | 3 | 34 | 0 | 8.1% |
| `RelationalOperatorReplacement` | 86 | 28 | 58 | 0 | 32.6% |
| `RemoveSideEffects` | 82 | 23 | 59 | 0 | 28.0% |
| `SwapTernary` | 14 | 1 | 13 | 0 | 7.1% |

Every verdict carries a one-line reason in the CSV. The first run of this campaign had 21 *not measurable* survivors — branches of an `#if` the macOS build leaves out, which no test on the machine can reach; discovery now skips those branches, and this run has none.

### Per project and operator

| Project | Operator | Generated | Detected | Survived | No coverage | Unviable | Kill rate | Cost per mutant |
|---|---|---|---|---|---|---|---|---|
| swift-algorithms | `ArithmeticOperatorReplacement` | 152 | 139 | 8 | 2 | 3 | 93.3% | 1426 ms |
| swift-algorithms | `BooleanLiteralReplacement` | 64 | 24 | 7 | 0 | 33 | 77.4% | 4275 ms |
| swift-algorithms | `LogicalOperatorReplacement` | 15 | 14 | 1 | 0 | 0 | 93.3% | 4587 ms |
| swift-algorithms | `NegateConditional` | 188 | 184 | 2 | 1 | 1 | 98.4% | 1468 ms |
| swift-algorithms | `RelationalOperatorReplacement` | 585 | 434 | 87 | 4 | 60 | 82.7% | 1359 ms |
| swift-algorithms | `RemoveSideEffects` | 49 | 33 | 16 | 0 | 0 | 67.3% | 7110 ms |
| swift-algorithms | `SwapTernary` | 59 | 59 | 0 | 0 | 0 | 100.0% | 847 ms |
| swift-argument-parser | `ArithmeticOperatorReplacement` | 39 | 14 | 2 | 0 | 23 | 87.5% | 1509 ms |
| swift-argument-parser | `BooleanLiteralReplacement` | 121 | 60 | 44 | 5 | 12 | 55.0% | 2160 ms |
| swift-argument-parser | `LogicalOperatorReplacement` | 31 | 20 | 11 | 0 | 0 | 64.5% | 1948 ms |
| swift-argument-parser | `NegateConditional` | 189 | 153 | 30 | 5 | 1 | 81.4% | 2060 ms |
| swift-argument-parser | `RelationalOperatorReplacement` | 266 | 137 | 72 | 9 | 48 | 62.8% | 1992 ms |
| swift-argument-parser | `RemoveSideEffects` | 120 | 46 | 54 | 13 | 7 | 40.7% | 2431 ms |
| swift-argument-parser | `SwapTernary` | 56 | 47 | 8 | 1 | 0 | 83.9% | 1721 ms |
| swift-cpd | `ArithmeticOperatorReplacement` | 138 | 120 | 13 | 0 | 5 | 90.2% | 1246 ms |
| swift-cpd | `BooleanLiteralReplacement` | 70 | 62 | 8 | 0 | 0 | 88.6% | 3642 ms |
| swift-cpd | `LogicalOperatorReplacement` | 47 | 39 | 8 | 0 | 0 | 83.0% | 3818 ms |
| swift-cpd | `NegateConditional` | 284 | 282 | 2 | 0 | 0 | 99.3% | 1919 ms |
| swift-cpd | `RelationalOperatorReplacement` | 300 | 265 | 35 | 0 | 0 | 88.3% | 3253 ms |
| swift-cpd | `RemoveSideEffects` | 128 | 114 | 9 | 0 | 5 | 92.7% | 3070 ms |
| swift-cpd | `SwapTernary` | 20 | 19 | 1 | 0 | 0 | 95.0% | 2919 ms |
| swift-log | `ArithmeticOperatorReplacement` | 5 | 2 | 3 | 0 | 0 | 40.0% | 306 ms |
| swift-log | `BooleanLiteralReplacement` | 28 | 19 | 6 | 3 | 0 | 67.9% | 333 ms |
| swift-log | `LogicalOperatorReplacement` | 7 | 7 | 0 | 0 | 0 | 100.0% | 109 ms |
| swift-log | `NegateConditional` | 27 | 25 | 2 | 0 | 0 | 92.6% | 155 ms |
| swift-log | `RelationalOperatorReplacement` | 55 | 42 | 6 | 1 | 6 | 85.7% | 141 ms |
| swift-log | `RemoveSideEffects` | 82 | 60 | 17 | 5 | 0 | 73.2% | 934 ms |
| swift-log | `SwapTernary` | 5 | 3 | 2 | 0 | 0 | 60.0% | 253 ms |
| swift-mutation-testing | `ArithmeticOperatorReplacement` | 70 | 45 | 7 | 0 | 18 | 86.5% | 12507 ms |
| swift-mutation-testing | `BooleanLiteralReplacement` | 127 | 92 | 33 | 0 | 2 | 73.6% | 27031 ms |
| swift-mutation-testing | `LogicalOperatorReplacement` | 62 | 49 | 13 | 0 | 0 | 79.0% | 19132 ms |
| swift-mutation-testing | `NegateConditional` | 287 | 276 | 11 | 0 | 0 | 96.2% | 4571 ms |
| swift-mutation-testing | `RelationalOperatorReplacement` | 361 | 282 | 77 | 0 | 2 | 78.6% | 16979 ms |
| swift-mutation-testing | `RemoveSideEffects` | 310 | 214 | 95 | 0 | 1 | 69.3% | 39433 ms |
| swift-mutation-testing | `SwapTernary` | 58 | 55 | 3 | 0 | 0 | 94.8% | 16951 ms |

## Reproducing the campaign

The campaign is three commands of a Foundation-only script, run from the root of this repository, plus one afternoon of reading. It needs a release build of the tool, Xcode's toolchain and the network for the clones.

```bash
swift build -c release
swift .github/scripts/operator-campaign/campaign.swift run .github/scripts/operator-campaign/corpus.json out/campaign \
    --tool "$PWD/.build/release/swift-mutation-testing"
```

`run` clones each project of [`corpus.json`](../.github/scripts/operator-campaign/corpus.json) at its commit into a temporary directory, runs the tool over it with `--no-cache --operator-tier experimental` and the project's own arguments (test target, exclusions, timeout), and leaves three files per project in the output directory: the JSON report, the console output and a `meta.json` with the commit, the tool and Swift versions, the machine, the date and the wall time. The entry `"."` is this repository, run from the working tree at `HEAD`. The whole corpus took about four hours on an Apple M4 Max in the record run, two and a half of them this repository's run; this repository's run alone took 67 minutes on 2026-10-08.

```bash
swift .github/scripts/operator-campaign/campaign.swift sample out/campaign --csv out/equivalence.csv
```

`sample` draws up to 20 survivors per (operator, project) with a fixed seed (20261001), so the same reports give the same draw, and writes them with empty `verdict` and `note` columns. Those are filled by hand, one survivor at a time, read in its source: `equivalent` when no input could make the mutated program behave differently through anything observable, `not-equivalent` when some input could, even if no test checks it, and `not-measurable` only for code the build leaves out. A doubt is resolved as *not equivalent*, which never demotes an operator. The verdicts of the record campaign are in [`operators/equivalence.csv`](operators/equivalence.csv), keyed by the mutant's fingerprint, so a rerun that draws the same survivor can carry its verdict over; `sample` refuses to overwrite a file that may hold reviews unless told `--force`.

```bash
swift .github/scripts/operator-campaign/campaign.swift aggregate out/campaign \
    --markdown Docs/operators/results.md --csv Docs/operators/results.csv --equivalence out/equivalence.csv
```

`aggregate` computes the [metrics](#metrics) and the tier by the criteria for every operator, and the per-cell table. `campaign.swift check` aggregates a small fixture under `.github/scripts/operator-campaign/check/` and compares with its expected output; the pull-request workflow runs it, so the arithmetic cannot drift unnoticed.

**What to expect between runs.** Discovery is deterministic: the same commit of a project and the same commit of the tool give the same mutants. Kills are stable — `swift-algorithms` reported the same 857 kills in six runs — and the survivors with them, so the sample, and the verdicts that carry over, barely move. What moves is the handful of mutants at the edge of the timeout, and the integrity warnings of a suite that is not deterministic under load (`swift-cpd` had 3 in one run and 7 in the next, on the same commits). A kill rate moving by more than a point between two runs on the same commits is a signal to look at the console output, not at the operator. A different machine changes the cost per mutant and the wall times, nothing else.

## Decisions

**2026-10-04 — first campaign.** Four projects with reports (`swift-algorithms`, `swift-argument-parser`, `swift-log`, this repository), 202 survivors reviewed.

- *Calibration: a project qualifies with 10 mutants of an operator, not 30.* The criteria asked for three projects with 30 mutants each; `LogicalOperatorReplacement` had them in two, because the `#if` conditions that inflated its count in `swift-log` stopped being mutants during this campaign. With 10, it is judged on three projects' data — 87.5% median kill rate, no unviable mutant, one equivalent in twelve — and lands in `conservative`. The other limits stayed as proposed.
- *The strict `default` limit (25% equivalent) was kept, and three operators left the default run.* Relaxing it to 50% would have kept `RelationalOperatorReplacement` and `RemoveSideEffects` in `default`, but their equivalents are systematic — `reserveCapacity(n ± 1)`, a `> 0` under a `!= 0` guard, a performance heuristic choosing between two paths with the same result, a dropped `hasher.combine` — and come back as survivors in every run. A default run that reports one false survivor in three is not a safe one, and `Relational` alone is more than half of the mutants of a typical project, so leaving it out also halves the run. They remain one flag away.
- *`ArithmeticOperatorReplacement` is `experimental`* on 61.5% equivalents (13 reviewed; `+ 1`/`- 1` in capacity hints and offsets) and 14.8% unviable.
- *Review verdicts are the reviewer's reading of the code, not an execution.* A doubt was resolved as *not equivalent*, which does not demote. 21 survivors were *not measurable*: branches of an `#if` the macOS build leaves out.
- *What the campaign changed in the tool.* Twelve defects in discovery and schematization were found and fixed before these numbers were taken; the report at a commit before them would not be comparable.

**2026-10-05 — record campaign, second run.** Five projects with reports: `swift-cpd` is back at the `main` that fixes its test helper, and the three items the first run left open are closed before the numbers were taken. 346 survivors reviewed in all, 199 of them new to this run.

- *Branches of an `#if` the build leaves out no longer produce mutants.* The first run's 21 *not measurable* survivors — Windows, FreeBSD and Android branches — were never a verdict on the operator; discovery now asks SwiftIfConfig which clauses the macOS build keeps, and drops the points in the others. An `#if` on a module the tool does not know keeps every clause. Across the four packages of the first run, 41 mutants disappeared this way — 9 in `swift-algorithms`, 17 in `swift-argument-parser`, 15 in `swift-log` — every one a survivor or a no-coverage mutant; not one kill changed.
- *This repository measures itself truthfully now.* The first run's 100% came with 147 integrity warnings: inside the tool's own sandbox the integration suites ran on `Fixtures/` as a tree of links, their pipeline escaped the sandbox, every one of them failed, and the stop rule ended most mutants' runs on that failure instead of on a test that saw the mutant — and a test whose *name* mentions `EXC_BAD_INSTRUCTION` made the parser call the kill a crash. Each integration test now works on a private copy of its fixture made of real files, the executors free their sandbox on every exit, three tests no longer measure time, and a failing test names the kill whatever a test's name says (#121). This run: 1275 mutants, 80.9%, 239 survivors — 94 of them reviewed, 15 equivalent — and 3 warnings. The README badge moves from 100% to the `default` tier's 93.4%.
- *One tier moved.* The three `conservative` operators keep their tier with more data behind them; `LogicalOperatorReplacement` now qualifies on four projects. `BooleanLiteralReplacement` leaves `default`: 17 of 61 reviewed survivors are equivalent, 27.9% against the 25% limit, where the first run had 4 of 33. The new ones are of a kind — `atomically:`, `withIntermediateDirectories:`, `isDirectory:` and `keepingCapacity:` flags whose other value changes nothing observable, hash tags, help flags and workaround properties nothing reads — and they would come back in every run. By the criteria it is `experimental`, and `default` is now the same set as `conservative`; the limit was not moved to keep it, for the reason the first entry gives: a default run that reports one false survivor in four is not a safe one. `RemoveSideEffects` (28.0%) and `ArithmeticOperatorReplacement` (27.3%, down from 61.5% now that 33 are reviewed instead of 13) sit just past the same line; `RelationalOperatorReplacement` stays at a third.

**2026-10-08 — this repository's self-run, repeated for the badge.** Only the entry `"."` of the corpus, with its arguments, at `3742959e24`, with the tool, Swift and machine of the record run; the other projects were not rerun, so the table under [Projects](#projects) keeps the record run.

- *1645 mutants, 99.2% over every operator.* 1595 killed, 13 survived, no timeouts, no mutant without coverage, 37 unviable, in 67 minutes. The 8 integrity warnings are listed in the console output and count as kills, as in the record run.
- *99.8% on the `default` tier.* Its three operators give 564 kills and 1 survivor (`NegateConditional` in `XcodeContainerLocator.swift`). The README badge shows this number.
- *No tier moved.* The rise from 80.9% comes from the tests added between the two runs, not from a change in the operators. The 13 survivors were not reviewed for equivalence, so this run gives the criteria nothing new.
