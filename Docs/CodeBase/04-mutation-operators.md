# Mutation Operators

← [Discovery Pipeline](03-discovery-pipeline.md) | Next: [Schematization →](05-schematization.md)

---

## Discovery/Operators/MutationOperator.swift

```swift
protocol MutationOperator: Sendable {
    var identifier: String { get }
    var summary: String { get }
    var explanation: String { get }
    var isLoopRisky: Bool { get }
    func mutations(in source: ParsedSource) -> [MutationPoint]
}

protocol OperatorVisitor: MutationSyntaxVisitor {
    static var operatorIdentifier: String { get }
    static var summary: String { get }
    static var explanation: String { get }
    static var isLoopRisky: Bool { get }  // default: false
}

struct VisitorOperator<Visitor: OperatorVisitor>: MutationOperator {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}

typealias RelationalOperatorReplacement = VisitorOperator<RelationalOperatorVisitor>
typealias BooleanLiteralReplacement = VisitorOperator<BooleanLiteralVisitor>
typealias LogicalOperatorReplacement = VisitorOperator<LogicalOperatorVisitor>
typealias ArithmeticOperatorReplacement = VisitorOperator<ArithmeticOperatorVisitor>
typealias NegateConditional = VisitorOperator<NegateConditionalVisitor>
typealias SwapTernary = VisitorOperator<SwapTernaryVisitor>
typealias RemoveSideEffects = VisitorOperator<RemoveSideEffectsVisitor>
```

All seven mutation operators conform to `MutationOperator`, and all seven are one generic type: `VisitorOperator` creates its visitor with `Visitor(source:)`, walks the AST once, and returns the collected mutation points. Each operator name is a typealias over it, so there is no file per operator; the sections below are named after the typealiases and describe their visitors.

What an operator is comes from its visitor's statics, read through the operator:

| Member | Description |
|---|---|
| `identifier` | The name reports, configuration files and `--operator` use; each visitor also stamps it on its `MutationPoint`s |
| `summary` | A short title — the SARIF rule's `shortDescription` |
| `explanation` | What the operator changes and what a survivor usually means — the SARIF rule's `fullDescription` |
| `isLoopRisky` | Whether a mutation inside a loop body could keep the loop from ending; `true` only for `ArithmeticOperatorReplacement` and `RemoveSideEffects` |

`OperatorRegistry` ([03 — Discovery Pipeline](03-discovery-pipeline.md)) holds the instances, and `SarifRuleCatalog` reads the names and descriptions from them.

---

## Discovery/Operators/MutationSyntaxVisitor.swift

```swift
class MutationSyntaxVisitor: SyntaxVisitor {
    let filePath: String
    let locationConverter: SourceLocationConverter
    var mutations: [MutationPoint]

    required init(source: ParsedSource)
    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind
}
```

Every operator's visitor inherits one rule: the condition of an `#if`, `#elseif` or `#else` clause is never visited. It is a compile-time expression — `#if DEBUG && !os(Windows)`, `#elseif compiler(<6.1)` — whose `&&`, `||`, `<` and literals are not code that runs, and a mutation there changes what compiles instead of what executes. The clause's code is walked as usual, whichever branch the build will take; the points that fall in a branch the host build leaves out are dropped afterwards, by the filter in [Inactive `#if` branches](#inactive-if-branches).

Base class for all operator visitors. Subclasses override `visit(_:)` methods to detect applicable nodes and append `MutationPoint` values to `mutations`. The initializer is `required` so that `VisitorOperator` can create any subclass from its type. `locationConverter` is the source's own (`ParsedSource.locationConverter`), not one built per visitor.

| Field | Description |
|---|---|
| `filePath` | Passed into every `MutationPoint` |
| `locationConverter` | Converts `AbsolutePosition` to line/column |
| `mutations` | Accumulated mutation points; read after `walk(_:)` |

---

## Discovery/Operators/ReplacementKind.swift

```swift
enum ReplacementKind: String, Sendable, Codable {
    case binaryOperator
    case prefixOperator
    case booleanLiteral
    case swapTernary
    case removeStatement
    case wrapWithNegation
}
```

Classifies the structural shape of the replacement, independent of the specific tokens involved.

| Case | Used by |
|---|---|
| `binaryOperator` | `RelationalOperatorReplacement`, `LogicalOperatorReplacement`, `ArithmeticOperatorReplacement` |
| `prefixOperator` | (reserved) |
| `booleanLiteral` | `BooleanLiteralReplacement` |
| `swapTernary` | `SwapTernary` |
| `removeStatement` | `RemoveSideEffects` |
| `wrapWithNegation` | `NegateConditional` |

---

## RelationalOperatorReplacement

```swift
typealias RelationalOperatorReplacement = VisitorOperator<RelationalOperatorVisitor>
```

Replaces comparison operators with their complements. Each token may produce multiple `MutationPoint` values (one per replacement).

**Replacement table:**

| Original | Replacements |
|---|---|
| `>` | `>=`, `<` |
| `>=` | `>`, `<=` |
| `<` | `<=`, `>` |
| `<=` | `<`, `>=` |
| `==` | `!=` |
| `!=` | `==` |

Visitor: `RelationalOperatorVisitor` — visits `BinaryOperatorExprSyntax`.

---

## BooleanLiteralReplacement

```swift
typealias BooleanLiteralReplacement = VisitorOperator<BooleanLiteralVisitor>
```

Flips `true` ↔ `false`.

Visitor: `BooleanLiteralVisitor` — visits `BooleanLiteralExprSyntax`.

---

## LogicalOperatorReplacement

```swift
typealias LogicalOperatorReplacement = VisitorOperator<LogicalOperatorVisitor>
```

Swaps `&&` ↔ `||`.

Visitor: `LogicalOperatorVisitor` — visits `BinaryOperatorExprSyntax` where the operator token is `&&` or `||`.

---

## ArithmeticOperatorReplacement

```swift
typealias ArithmeticOperatorReplacement = VisitorOperator<ArithmeticOperatorVisitor>
```

Swaps arithmetic operators: `+` ↔ `-`, `*` ↔ `/`, `%` → `*`.

Skips `+` and `-` when either operand is a string literal, which would otherwise produce `"a" - "b"`. The check walks the token's enclosing expression list to find the operands; a `+` that is not part of a binary expression at all — an operator *declaration*, for instance — has no operands to inspect and is mutated like any other.

The `*` of an availability check, `#available(macOS 10.15, *)` or `@available(*, deprecated)`, is tokenized as a binary operator too; its parent is an `AvailabilityArgumentSyntax`, and the visitor leaves it alone.

Visitor: `ArithmeticOperatorVisitor` — visits `BinaryOperatorExprSyntax`.

---

## NegateConditional

```swift
typealias NegateConditional = VisitorOperator<NegateConditionalVisitor>
```

Wraps a condition expression in `!()`.

Visitor: `NegateConditionalVisitor` — visits `ConditionElementSyntax`.

---

## SwapTernary

```swift
typealias SwapTernary = VisitorOperator<SwapTernaryVisitor>
```

Swaps the true and false branches of a ternary expression.

The mutation is anchored on the **whole** ternary — condition, `?`, both branches — not on the condition alone. Anchoring on the condition turns `flag ? a : b` into `flag ? b : a ? a : b`, which either fails to compile or means something else entirely. In a chain (`a ? b : c ? d : e`) the visitor walks back to the nearest preceding ternary to find where its own condition starts, so each link swaps its own branches.

A ternary whose branches are identical is skipped at discovery: swapping them produces the same program, and an equivalent mutant can only ever be reported as survived.

The condition, the branches and the original text are joined from the expression list's elements; the first element's leading trivia is dropped, so a comment above the statement is not part of the mutation and the text starts where its offset says.

Visitor: `SwapTernaryVisitor` — visits `UnresolvedTernaryExprSyntax`.

---

## RemoveSideEffects

```swift
typealias RemoveSideEffects = VisitorOperator<RemoveSideEffectsVisitor>
```

Removes standalone function call statements. Three things are never removed, each because removing them produces a mutant that cannot compile rather than one the tests could catch:

**Deny-list:** `print`, `debugPrint`, `assert`, `assertionFailure`, `precondition`, `preconditionFailure`, `fatalError` — plus `super.init` and `self.init`, since an initializer that does not delegate does not compile.

**Sole statement of a body.** A call that is the only statement of a closure, an accessor block, a `switch` case, or the body of a function, initializer, deinitializer or accessor is left alone: removing it empties the body, and an empty `case` is a compile error for the whole file, not just for that mutant. `if`, `for`, `while`, `do` and `defer` bodies may be emptied and are still mutated.

**Inside a `while` or `repeat`.** Handled by the infinite-loop filter below, not by the operator itself.

Visitor: `RemoveSideEffectsVisitor` — visits `CodeBlockItemSyntax` whose expression is a function call. The reported line, column and offset come from the node's position after leading trivia, so a call preceded by a comment is reported at the call.

---

## Suppression

### Discovery/Suppression/SuppressionAnnotationExtractor.swift

```swift
struct SuppressionAnnotationExtractor: Sendable {
    func extractSuppressedRanges(from syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]
}
```

Delegates to `SuppressionVisitor` and returns the collected suppressed byte ranges.

---

### Discovery/Suppression/SuppressionFilter.swift

```swift
struct SuppressionFilter: MutationExclusion {
    func ranges(in syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]
}
```

A `MutationExclusion` whose ranges are the suppressed ones `SuppressionAnnotationExtractor` finds. Its `ranges(in:)` for a `ParsedSource` hands the extractor the file's converter; given only the syntax, the extractor builds one. `MutationExclusion` declares both forms, the `ParsedSource` one defaulting to the syntax one. It keeps the default `applies(to:)`, so the shared `filter` removes any `MutationPoint` whose `utf8Offset` (as `AbsolutePosition`) falls within a suppressed range.

---

### Discovery/Suppression/SuppressionVisitor.swift

```swift
final class SuppressionVisitor: SyntaxVisitor {
    static let disableDirective: String            // "swift-mutation-testing:disable"
    static let disableNextLineDirective: String    // "swift-mutation-testing:disable-next-line"
    init(converter: SourceLocationConverter)
    private(set) var suppressedRanges: [Range<AbsolutePosition>]
    static func directive(in piece: TriviaPiece) -> String?
}
```

Records two kinds of range:

- **A declaration** whose leading trivia holds a `//` comment starting with `swift-mutation-testing:disable`, or which carries the `@SwiftMutationTestingDisabled` attribute (honoured for projects that declare it; Swift rejects it otherwise): the declaration from its first token to its last.
- **A line**: for every `//` comment starting with `swift-mutation-testing:disable-next-line`, in any token's leading or trailing trivia, the whole line after the comment's, located with the `SourceLocationConverter`.

`directive(in:)` takes the comment's first word after `//`, so text after it is a free reason and a lookalike (`disabled`, a block comment, the word mid-sentence) does nothing.

**Supported declaration kinds:**

`FunctionDeclSyntax`, `InitializerDeclSyntax`, `DeinitializerDeclSyntax`, `SubscriptDeclSyntax`, `ClassDeclSyntax`, `StructDeclSyntax`, `EnumDeclSyntax`, `ActorDeclSyntax`, `ExtensionDeclSyntax`, `VariableDeclSyntax`. Before the comments, initializers, `deinit`, subscripts and actors were not visited at all, though the documentation listed initializers.

---

## Infinite-loop prevention

Two operators can turn a terminating loop into one that never ends: `ArithmeticOperatorReplacement`, which can flip the step that moves an index towards its bound, and `RemoveSideEffects`, which can delete the statement that advances it. A mutant like that does not fail the tests — it hangs them, and the run pays the full `--timeout` for a verdict of `Timeout` that says nothing about the test suite.

Mutation points of those two operators — the ones whose `isLoopRisky` is `true`, collected in `OperatorRegistry.loopRiskyNames` — are therefore dropped at discovery when they fall inside the body of a `while` or a `repeat`. `for` loops are left alone: they iterate a sequence, and neither operator can make that sequence infinite.

### Discovery/InfiniteLoopPrevention/InfiniteLoopBodyVisitor.swift

```swift
final class InfiniteLoopBodyVisitor: SyntaxVisitor {
    private(set) var loopBodyRanges: [Range<AbsolutePosition>]
}
```

Collects the body range of every `WhileStmtSyntax` and `RepeatStmtSyntax`, nested ones included.

### Discovery/InfiniteLoopPrevention/InfiniteLoopBodyExtractor.swift

```swift
struct InfiniteLoopBodyExtractor: Sendable {
    func extractLoopBodyRanges(from syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]
}
```

Walks the file once with `InfiniteLoopBodyVisitor` and returns what it found.

### Discovery/InfiniteLoopPrevention/InfiniteLoopFilter.swift

```swift
struct InfiniteLoopFilter: MutationExclusion {
    var riskyOperators: Set<String> = OperatorRegistry.loopRiskyNames
    func ranges(in syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]
    func applies(to point: MutationPoint) -> Bool
}
```

A `MutationExclusion` whose ranges are the loop bodies `InfiniteLoopBodyExtractor` finds, and which applies only to points of `riskyOperators`. The shared `filter` removes the points of the risky operators whose `utf8Offset` falls inside a collected range. Every other operator passes through untouched, and a file with no `while` or `repeat` returns its points unchanged without any range checks.

`MutantDiscoveryStage.standardExclusions` applies this after `SuppressionFilter`, so a suppressed region is never even considered.

---

## Inactive `#if` branches

A mutant inside an `#if os(Windows)` or `#if canImport(Glibc)` branch compiles to nothing on the macOS host: no test can reach it, it can only survive, and it would count against the operator for a flaw that is not the operator's. Those points are dropped at discovery. The decision of which clause is active is SwiftIfConfig's — the same module the compiler's tooling uses — given a description of the host build.

### Discovery/IfConfig/HostBuildConfiguration.swift

```swift
struct HostBuildConfiguration: BuildConfiguration {
    static let modulesPresent: Set<String>
    static let modulesAbsent: Set<String>
    static var hostArchitecture: String
    static let hostCompilerVersion: VersionTuple
    init(compilerVersion: VersionTuple = Self.hostCompilerVersion)
}
```

The build the tool runs: macOS, the host architecture, `DEBUG` and `SWIFT_PACKAGE` set, the Objective-C runtime, Mach-O, 64-bit pointers, language version 6 and the compiler the tool was built with. Everything but `canImport` is delegated to SwiftIfConfig's `StaticBuildConfiguration`. `canImport` is answered from two curated lists — Apple's and the toolchain's modules present, the other platforms' C libraries and UI frameworks absent — and throws for any other module, which is the signal the extractor below reads as *undecidable*. The type is not `Sendable`, so the extractor builds one per file.

### Discovery/IfConfig/InactiveRegionExtractor.swift

```swift
struct InactiveRegionExtractor: Sendable {
    init(compilerVersion: VersionTuple = HostBuildConfiguration.hostCompilerVersion)
    func extractInactiveRanges(from syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]
}
```

Asks SwiftIfConfig for the configured regions of the file and returns the range of every clause that is not active — *inactive* ones and *unparsed* ones alike, the latter being the branches a `swift(…)` or `compiler(…)` check turns off. An `#if` whose condition cannot be decided — a `canImport` of a module in neither list, a malformed condition — keeps every one of its clauses, because SwiftIfConfig would otherwise take its `#else` for the active one; and should such an error not be traceable to a clause, the file keeps everything. Dropping a real mutant is the error this code avoids.

### Discovery/IfConfig/InactiveRegionFilter.swift

```swift
struct InactiveRegionFilter: MutationExclusion {
    func ranges(in syntax: SourceFileSyntax) -> [Range<AbsolutePosition>]
}
```

A `MutationExclusion` whose ranges are the ones `InactiveRegionExtractor` returns. It keeps the default `applies(to:)`, so the shared `filter` removes any point whose `utf8Offset` falls inside a collected range, for every operator. `MutantDiscoveryStage.standardExclusions` applies it last, after the infinite-loop filter.

---

← [Discovery Pipeline](03-discovery-pipeline.md) | Next: [Schematization →](05-schematization.md)
