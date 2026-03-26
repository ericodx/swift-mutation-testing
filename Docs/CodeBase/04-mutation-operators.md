# Mutation Operators

← [Discovery Pipeline](03-discovery-pipeline.md) | Next: [Schematization →](05-schematization.md)

---

## Discovery/Operators/MutationOperator.swift

```swift
protocol MutationOperator: Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

All seven mutation operators conform to this protocol. Each implementation creates its visitor, walks the AST, and returns the collected mutation points.

---

## Discovery/Operators/MutationSyntaxVisitor.swift

```swift
class MutationSyntaxVisitor: SyntaxVisitor {
    let filePath: String
    let locationConverter: SourceLocationConverter
    var mutations: [MutationPoint]

    init(filePath: String, locationConverter: SourceLocationConverter)
}
```

Base class for all operator visitors. Subclasses override `visit(_:)` methods to detect applicable nodes and append `MutationPoint` values to `mutations`.

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
struct RelationalOperatorReplacement: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
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
struct BooleanLiteralReplacement: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

Flips `true` ↔ `false`.

Visitor: `BooleanLiteralVisitor` — visits `BooleanLiteralExprSyntax`.

---

## LogicalOperatorReplacement

```swift
struct LogicalOperatorReplacement: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

Swaps `&&` ↔ `||`.

Visitor: `LogicalOperatorVisitor` — visits `BinaryOperatorExprSyntax` where the operator token is `&&` or `||`.

---

## ArithmeticOperatorReplacement

```swift
struct ArithmeticOperatorReplacement: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

Swaps arithmetic operators: `+` ↔ `-`, `*` ↔ `/`, `%` → `*`.

Skips nodes where either operand is a string literal to avoid producing invalid Swift.

Visitor: `ArithmeticOperatorVisitor` — visits `BinaryOperatorExprSyntax`.

---

## NegateConditional

```swift
struct NegateConditional: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

Wraps a condition expression in `!()`.

Visitor: `NegateConditionalVisitor` — visits `ConditionElementSyntax`.

---

## SwapTernary

```swift
struct SwapTernary: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

Swaps the true and false branches of a ternary expression.

Visitor: `SwapTernaryVisitor` — visits `UnresolvedTernaryExprSyntax`.

---

## RemoveSideEffects

```swift
struct RemoveSideEffects: MutationOperator, Sendable {
    func mutations(in source: ParsedSource) -> [MutationPoint]
}
```

Removes standalone function call statements. Skips calls to a fixed deny-list of safety-critical functions.

**Deny-list:** `print`, `debugPrint`, `assert`, `assertionFailure`, `precondition`, `preconditionFailure`, `fatalError`

Visitor: `RemoveSideEffectsVisitor` — visits `CodeBlockItemSyntax` whose expression is a function call.

---

## Suppression

### Discovery/Suppression/SuppressionAnnotationExtractor.swift

```swift
struct SuppressionAnnotationExtractor: Sendable {
    func extract(from source: ParsedSource) -> [Range<AbsolutePosition>]
}
```

Delegates to `SuppressionVisitor` and returns the collected suppressed byte ranges.

---

### Discovery/Suppression/SuppressionFilter.swift

```swift
struct SuppressionFilter: Sendable {
    func filter(_ points: [MutationPoint], suppressedRanges: [Range<AbsolutePosition>]) -> [MutationPoint]
}
```

Removes any `MutationPoint` whose `utf8Offset` (as `AbsolutePosition`) falls within a suppressed range.

---

### Discovery/Suppression/SuppressionVisitor.swift

```swift
final class SuppressionVisitor: SyntaxVisitor {
    var suppressedRanges: [Range<AbsolutePosition>]
}
```

Walks the AST looking for the `@SwiftMutationTestingDisabled` attribute. When found on a supported declaration, the declaration's full source range is recorded in `suppressedRanges`.

**Supported declaration kinds:**

`FunctionDeclSyntax`, `InitializerDeclSyntax`, `ClassDeclSyntax`, `StructDeclSyntax`, `EnumDeclSyntax`, `ExtensionDeclSyntax`, `VariableDeclSyntax`

---

← [Discovery Pipeline](03-discovery-pipeline.md) | Next: [Schematization →](05-schematization.md)
