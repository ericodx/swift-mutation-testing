# Discovery Pipeline

← [Configuration](02-configuration.md) | Next: [Mutation Operators →](04-mutation-operators.md)

---

## Discovery/DiscoveryPipeline.swift

```swift
struct DiscoveryPipeline: Sendable {
    static let allOperatorNames: [String]
    func run(input: DiscoveryInput) async throws -> RunnerInput
}
```

Entry point for the discovery phase. Runs four stages sequentially and assembles the `RunnerInput` for the execution pipeline.

```mermaid
flowchart TD
    IN[DiscoveryInput] --> FD[FileDiscoveryStage]
    FD --> PA[ParsingStage]
    PA --> MD[MutantDiscoveryStage\nwith resolved operators]
    MD --> SC[SchematizationStage]
    SC --> OUT[RunnerInput]
```

`allOperatorNames` is the ordered list of all registered operator identifiers. `ConfigurationFileWriter` uses it to populate the operators section of the generated YAML.

**Operator registry** (registration order is fixed):

| Index | Identifier |
|---|---|
| 0 | `RelationalOperatorReplacement` |
| 1 | `BooleanLiteralReplacement` |
| 2 | `LogicalOperatorReplacement` |
| 3 | `ArithmeticOperatorReplacement` |
| 4 | `NegateConditional` |
| 5 | `SwapTernary` |
| 6 | `RemoveSideEffects` |

When `input.operators` is empty, all seven operators are active. Otherwise only the listed identifiers are used.

---

## Discovery/Pipeline/DiscoveryInput.swift

```swift
struct DiscoveryInput: Sendable {
    let projectPath: String
    let scheme: String
    let destination: String
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let sourcesPath: String
    let excludePatterns: [String]
    let operators: [String]
}
```

| Field | Description |
|---|---|
| `projectPath` | Absolute path to the Xcode project root |
| `scheme` | Xcode scheme used for the build |
| `destination` | `xcodebuild` destination specifier |
| `timeout` | Per-mutant test timeout in seconds |
| `concurrency` | Number of parallel test workers |
| `noCache` | Disable result cache |
| `sourcesPath` | Root directory for Swift source file collection |
| `excludePatterns` | Glob patterns for files to skip |
| `operators` | Active operator identifiers (empty = all) |

---

## Discovery/Pipeline/FileDiscoveryStage.swift

```swift
struct FileDiscoveryStage: Sendable {
    func run(input: DiscoveryInput) throws -> [SourceFile]
}
```

Recursively enumerates the directory tree under `input.sourcesPath` using `FileManager.enumerator`. Returns one `SourceFile` per discovered `.swift` file.

**Fixed exclusions** (applied regardless of `excludePatterns`):

`/Tests/`, `/Specs/`, `Mock.swift`, `Stub.swift`, `Fake.swift`, `/.build/`, `DerivedData`, `/.xmr-`, `Pods/`, `Carthage/`, `vendor/`, `Generated/`

Files matching any `excludePatterns` glob pattern are also excluded.

Throws `FileDiscoveryError.sourcesPathNotFound` if `sourcesPath` does not exist.

---

## Discovery/Pipeline/FileDiscoveryError.swift

```swift
enum FileDiscoveryError: Error, Sendable {
    case sourcesPathNotFound(String)
}
```

| Case | Payload | Condition |
|---|---|---|
| `sourcesPathNotFound` | `String` — the missing path | `sourcesPath` directory does not exist |

---

## Discovery/Pipeline/ParsingStage.swift

```swift
struct ParsingStage: Sendable {
    func run(sourceFiles: [SourceFile]) async -> [ParsedSource]
}
```

Parses each `SourceFile` into a SwiftSyntax AST using `withTaskGroup` for concurrency. Files that fail to parse are silently dropped. The output array contains only successfully parsed files.

---

## Discovery/Pipeline/MutantDiscoveryStage.swift

```swift
struct MutantDiscoveryStage: Sendable {
    init(operators: [any MutationOperator])
    func run(sources: [ParsedSource]) async -> [MutationPoint]
}
```

Applies all active operators concurrently across sources via `withTaskGroup`. For each source:

1. Extracts suppressed ranges via `SuppressionAnnotationExtractor`
2. Collects mutation points from every operator
3. Removes suppressed points via `SuppressionFilter`

Results are sorted by `filePath` then `utf8Offset`.

---

## Discovery/Pipeline/SchematizationStage.swift

```swift
struct SchematizationStage: Sendable {
    func run(mutationPoints: [MutationPoint], sources: [ParsedSource]) -> SchematizationResult
}
```

Transforms mutation points into the final representation consumed by the execution pipeline.

```mermaid
flowchart TD
    MP[MutationPoint sorted by file/offset] --> ASSIGN[assign global index\nclassify schematizable]
    ASSIGN --> GROUP[group by file]
    GROUP --> SCHEMA[SchemataGenerator per file\n→ SchematizedFile]
    GROUP --> REWRITE[MutationRewriter per incompatible\n→ mutatedSourceContent]
    SCHEMA & REWRITE --> RESULT[SchematizationResult]
```

Assigns a globally unique sequential index to each mutation point (sorted by file path, then UTF-8 offset). The index becomes the mutant ID suffix in `"swift-mutation-testing_<index>"`.

The static `supportFileContent` declares `__swiftMutationTestingID` as a computed property reading from `ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"]`.

---

## Discovery/Pipeline/SchematizationResult.swift

```swift
struct SchematizationResult: Sendable {
    let schematizedFiles: [SchematizedFile]
    let descriptors: [MutantDescriptor]
    let supportFileContent: String
}
```

| Field | Description |
|---|---|
| `schematizedFiles` | One entry per source file that contains schematizable mutations |
| `descriptors` | All mutants (schematizable and incompatible), sorted by index |
| `supportFileContent` | The `__swiftMutationTestingID` global declaration |

---

## Discovery/Pipeline/SourceFile.swift

```swift
struct SourceFile: Sendable {
    let path: String
    let content: String
}
```

| Field | Description |
|---|---|
| `path` | Absolute path to the `.swift` file |
| `content` | Raw UTF-8 source text |

---

## Discovery/Pipeline/ParsedSource.swift

```swift
struct ParsedSource: Sendable {
    let file: SourceFile
    let syntax: SourceFileSyntax
}
```

| Field | Description |
|---|---|
| `file` | The source file with its raw text |
| `syntax` | SwiftSyntax AST root node |

---

## Discovery/Pipeline/MutationPoint.swift

```swift
struct MutationPoint: Sendable {
    let filePath: String
    let line: Int
    let column: Int
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String
    let operatorIdentifier: String
    let replacement: ReplacementKind
    var description: String { get }
}
```

Represents a single applicable mutation before schematization.

| Field | Description |
|---|---|
| `filePath` | Absolute path to the source file |
| `line` | 1-based line number |
| `column` | 1-based column number |
| `utf8Offset` | Byte offset in UTF-8 encoded content |
| `originalText` | Token(s) before mutation |
| `mutatedText` | Token(s) after mutation |
| `operatorIdentifier` | Name of the operator that produced this point |
| `replacement` | Structural kind of the replacement |
| `description` | Computed: `"\(originalText) → \(mutatedText)"` |

---

## Discovery/Pipeline/MutantDescriptor.swift

```swift
struct MutantDescriptor: Sendable, Codable {
    let id: String
    let filePath: String
    let line: Int
    let column: Int
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String
    let operatorIdentifier: String
    let replacementKind: ReplacementKind
    let description: String
    let isSchematizable: Bool
    let mutatedSourceContent: String?
}
```

The canonical representation of a mutant carried through the execution pipeline and into reports.

| Field | Description |
|---|---|
| `id` | `"swift-mutation-testing_<index>"` — unique per run |
| `isSchematizable` | `true` if the mutation falls inside a function body |
| `mutatedSourceContent` | Complete source file with the mutation applied; `nil` for schematizable mutants |

All position fields (`line`, `column`, `utf8Offset`) match those in the originating `MutationPoint`.

---

← [Configuration](02-configuration.md) | Next: [Mutation Operators →](04-mutation-operators.md)
