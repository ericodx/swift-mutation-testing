# Sandbox & Build

← [Schematization](05-schematization.md) | Next: [Execution →](07-execution.md)

---

## Sandbox/SandboxFactory.swift

```swift
struct SandboxFactory: Sendable {
    func create(
        projectPath: String,
        schematizedFiles: [SchematizedFile],
        supportFileContent: String
    ) async throws -> Sandbox

    func create(
        projectPath: String,
        mutatedFilePath: String,
        mutatedContent: String
    ) async throws -> Sandbox
}
```

Creates an isolated copy of the Xcode project in `$TMPDIR/xmr-<UUID>/`. The original project is never modified.

**Two overloads:**

| Overload | Used by | Description |
|---|---|---|
| `(projectPath:schematizedFiles:supportFileContent:)` | `MutantExecutor` for schematizable path | Embeds all schematized files; injects support file; disables SwiftLint phases |
| `(projectPath:mutatedFilePath:mutatedContent:)` | `IncompatibleMutantExecutor` | Writes a single mutated file; no support file injection |

**Copy strategy:**

```mermaid
flowchart TD
    DIR[directory item] --> SKIP{skip?}
    SKIP -- .build / DerivedData / .xmr-* --> DROP[skip]
    SKIP -- no --> XCODEPROJ{.xcodeproj?}
    XCODEPROJ -- yes --> PROJ[xcuserdata → mkdir\nxcshareddata → copy\neverything else → symlink]
    XCODEPROJ -- no --> RECURSE[recurse into directory]
    FILE[file item] --> SCHEMATIZED{schematized?}
    SCHEMATIZED -- yes --> WRITE[write schematized content\n+ fixEmptySwitchCaseBodies]
    SCHEMATIZED -- no --> MUTATED{mutated?}
    MUTATED -- yes --> WRITEM[write mutated content]
    MUTATED -- no --> SYMLINK[symlink to original]
```

**Post-processing steps (schematizable overload only):**

1. `injectSupportFile` — writes `__SMTSupport.swift` to the sandbox `Sources/` directory (or appends to the first schematized file if no `Sources/` directory exists). When the destination is an Xcode target (not macOS/SPM), transforms the computed property form to a `nonisolated(unsafe)` stored variable.

2. `disableSwiftLintBuildPhases` — patches `project.pbxproj`, replacing the `shellScript` of every `PBXShellScriptBuildPhase` that contains `swiftlint` with `exit 0\n`.

3. `fixEmptySwitchCaseBodies` — post-processes each schematized file after writing. Inserts a `break` statement into any `case "..."` block immediately followed by another case or default, preventing Swift compiler errors when `RemoveSideEffects` removes the only statement in a function body.

---

## Sandbox/Sandbox.swift

```swift
struct Sandbox: Sendable {
    let rootURL: URL
    func cleanup() throws
}
```

A lightweight wrapper around the sandbox root URL.

| Field | Description |
|---|---|
| `rootURL` | Absolute URL of the `xmr-<UUID>` directory in `$TMPDIR` |

`cleanup()` removes the entire `rootURL` directory tree via `FileManager.default.removeItem(at:)`.

---

## Build/BuildStage.swift

```swift
struct BuildStage: Sendable {
    let launcher: any ProcessLaunching
    func build(
        sandbox: Sandbox,
        scheme: String,
        destination: String,
        timeout: Double
    ) async throws -> BuildArtifact
}
```

Runs `xcodebuild build-for-testing` once inside the sandbox.

```mermaid
flowchart TD
    A[xcodebuild build-for-testing\n-scheme -destination\n-derivedDataPath sandbox/.xmr-derived-data] --> B{exit code?}
    B -- non-zero --> FAIL[throw BuildError.compilationFailed]
    B -- 0 --> C[search Build/Products for .xctestrun]
    C -- not found --> NFE[throw BuildError.xctestrunNotFound]
    C -- found --> D[Data(contentsOf: xctestrunURL)]
    D --> E[XCTestRunPlist(data)]
    E -- nil --> NFE2[throw BuildError.xctestrunNotFound]
    E -- plist --> F[BuildArtifact]
```

Auto-detects project format: prefers `-workspace` if a `.xcworkspace` exists, falls back to `-project` for `.xcodeproj`, or omits both for SPM packages.

Derived data is placed at `<sandbox>/.xmr-derived-data` to keep it inside the sandbox directory.

---

## Build/BuildArtifact.swift

```swift
struct BuildArtifact: Sendable {
    let derivedDataPath: String
    let xctestrunURL: URL
    let plist: XCTestRunPlist
}
```

| Field | Description |
|---|---|
| `derivedDataPath` | Path passed to `-derivedDataPath`; reused by `test-without-building` |
| `xctestrunURL` | URL of the `.xctestrun` file in `Build/Products` |
| `plist` | Parsed representation of the `.xctestrun` plist |

---

## Build/BuildError.swift

```swift
enum BuildError: Error, Sendable {
    case compilationFailed
    case xctestrunNotFound
}
```

| Case | Condition | Handling |
|---|---|---|
| `compilationFailed` | `xcodebuild` exits with non-zero code | Caught by `MutantExecutor`; triggers fallback path |
| `xctestrunNotFound` | No `.xctestrun` in `Build/Products`, or plist parse failure | Propagates; fatal |

---

← [Schematization](05-schematization.md) | Next: [Execution →](07-execution.md)
