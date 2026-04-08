# v1.3.0 — Sandbox lifecycle management and signal-safe cleanup

Orphaned sandbox directories from interrupted runs are now cleaned up automatically at startup, and active sandboxes are removed on SIGINT/SIGTERM — preventing the disk leak that could accumulate hundreds of gigabytes in `$TMPDIR`.

---

### What's new

**Automatic orphaned sandbox cleanup**
- `SandboxCleaner.removeOrphaned()` scans `$TMPDIR` at startup and removes all directories prefixed with `xmr-` left behind by previous interrupted runs
- No user action needed — cleanup runs once before any new execution begins

**Signal-safe active sandbox cleanup**
- `SandboxCleaner.installSignalHandlers()` installs `SIGINT` and `SIGTERM` handlers at process startup
- When a signal is received during execution, the active sandbox directory is removed before the process exits
- Uses a `nonisolated(unsafe)` C pointer at module scope — necessary because C signal handlers cannot capture Swift context
- `SandboxCleaner.register()` / `deregister()` track the active sandbox throughout the execution lifecycle

**Testable signal handler architecture**
- `handleSignal` delegates cleanup to `cleanupActiveSandbox()` and exit to a replaceable `@convention(c)` function pointer (`sandboxCleanerExitHandler`)
- Tests retrieve the installed handler via `signal()`, swap the exit handler for a stub, and invoke the handler directly — achieving full coverage without subprocess tricks or `fork()`

---

### Architecture changes

**New type: `SandboxCleaner`** — an `enum` (namespace) managing the full sandbox lifecycle:

| Method | Responsibility |
|---|---|
| `removeOrphaned(in:)` | Scans a directory for `xmr-*` entries and removes them |
| `register(_:)` | Stores the active sandbox path in a C pointer for signal handler access |
| `deregister()` | Clears the stored path and deallocates the pointer |
| `installSignalHandlers()` | Installs `SIGINT`/`SIGTERM` handlers that clean up and exit |
| `cleanupActiveSandbox()` | Removes the registered sandbox directory (extracted for testability) |

**MutantExecutor integration** — `register(sandbox)` is called after sandbox creation; `deregister()` is called in both the success and error cleanup paths, ensuring the signal handler always has the correct state.

**Entry point** — `main()` calls `installSignalHandlers()` and `removeOrphaned()` before any execution begins.

---

### Bug fixes

- Fixed disk leak where interrupted mutation testing runs left `xmr-*` sandbox directories in `$TMPDIR` indefinitely — accumulating up to hundreds of gigabytes over repeated interrupted sessions
- Fixed `rewriteForIncompatible` returning nil for source files deleted between retry and rewrite — now correctly marks the mutant as `.unviable` with explicit test coverage

---

### Test coverage

- 12 unit tests for `SandboxCleaner` covering: orphan removal, nested content, mixed entries, register/deregister lifecycle, `cleanupActiveSandbox`, signal handler installation, and direct `handleSignal` invocation with stubbed exit
- `handleSignal` tested by retrieving the installed C function pointer and invoking it with a `@convention(c)` exit stub — full branch coverage without process termination
- Strengthened `MutantExecutor` test for `rewriteForIncompatible` line 454: new `SPMRetryWithFileDeletionMock` deletes the source file during the retry build, verifying the nil-return path produces `.unviable`

---

### Requirements

- macOS 15+
- Swift 6.2+
- Xcode project with a valid scheme and test target, **or** an SPM package with a test target

---

### Installation

See the [Installation Guide](https://github.com/ericodx/swift-mutation-testing/blob/main/Docs/INSTALLATION.MD) for Homebrew, pre-built binary, and build from source instructions.
