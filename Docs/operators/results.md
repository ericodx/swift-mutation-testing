| Operator | Tier by the criteria | Projects (≥ 10 mutants) | Median kill rate | Unviable | Equivalent (reviewed) | Cost per mutant |
|---|---|---|---|---|---|---|
| `ArithmeticOperatorReplacement` | experimental | 4 of 5 | 88.9% | 12.1% | 27.3% (33) | 2969 ms |
| `BooleanLiteralReplacement` | experimental | 5 of 5 | 73.6% | 11.5% | 27.9% (61) | 11050 ms |
| `LogicalOperatorReplacement` | conservative | 4 of 5 | 81.0% | 0.0% | 9.1% (33) | 9232 ms |
| `NegateConditional` | conservative | 5 of 5 | 96.2% | 0.2% | 8.1% (37) | 2593 ms |
| `RelationalOperatorReplacement` | experimental | 5 of 5 | 82.7% | 7.4% | 32.6% (86) | 5669 ms |
| `RemoveSideEffects` | experimental | 5 of 5 | 69.3% | 1.9% | 28.0% (82) | 19619 ms |
| `SwapTernary` | conservative | 4 of 5 | 94.9% | 0.0% | 7.1% (14) | 6006 ms |

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
