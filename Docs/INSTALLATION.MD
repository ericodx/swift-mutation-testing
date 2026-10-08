# Installation

## Requirements

- macOS 15 or later
- Xcode, whose toolchain builds and tests the projects the tool runs on (`xcodebuild`, `xcrun`, `swift`)
- Swift 6.2 or later, which comes with Xcode 26 (for building from source; `Package.swift` declares `swift-tools-version: 6.2`)

---

## Homebrew (recommended)

The fastest way to install `swift-mutation-testing` on macOS.

```bash
brew tap ericodx/homebrew-tools
brew install swift-mutation-testing
```

Verify the installation:

```bash
swift-mutation-testing --version
# swift-mutation-testing 0.1.0 [arm64-macos15]
```

### Updating

```bash
brew upgrade swift-mutation-testing
```

### Uninstalling

```bash
brew uninstall swift-mutation-testing
brew untap ericodx/homebrew-tools  # optional
```

---

## Download a pre-built binary

Pre-built binaries are published with every release on the [GitHub Releases page](https://github.com/ericodx/swift-mutation-testing/releases).

```bash
# Replace X.Y.Z with the desired version
VERSION="0.1.0"
curl -L "https://github.com/ericodx/swift-mutation-testing/releases/download/v${VERSION}/swift-mutation-testing-v${VERSION}-macos.tar.gz" \
  | tar -xz

# Move to a directory in your PATH
sudo mv swift-mutation-testing /usr/local/bin/
```

Verify:

```bash
swift-mutation-testing --version
```

---

## Build from source

Requires Swift 6.2 or later. Check your version with `swift --version`.

```bash
git clone https://github.com/ericodx/swift-mutation-testing.git
cd swift-mutation-testing
swift build -c release
```

The compiled binary is at `.build/release/swift-mutation-testing`. Copy it to a directory in your `PATH`:

```bash
sudo cp .build/release/swift-mutation-testing /usr/local/bin/
```

---

## Run without installing (SPM)

If you have the repository cloned locally, you can run the tool directly without a global install:

```bash
# From the swift-mutation-testing repository root
swift run swift-mutation-testing /path/to/your/project --scheme MyScheme --destination "platform=macOS"

# Or point to the package from another directory
swift run --package-path /path/to/swift-mutation-testing swift-mutation-testing /path/to/your/project --scheme MyScheme --destination "platform=macOS"
```

---

## Claude Code plugin (AI coding agents)

The repository is also a [Claude Code](https://code.claude.com) plugin marketplace. Its plugin adds a skill that teaches Claude to run `swift-mutation-testing`, read the report and write the tests that kill surviving mutants. The skill calls the CLI, so install the CLI first with one of the methods above.

From your shell:

```bash
claude plugin marketplace add ericodx/swift-mutation-testing
claude plugin install swift-mutation-testing@swift-mutation-testing
```

Or inside a Claude Code session:

```
/plugin marketplace add ericodx/swift-mutation-testing
/plugin install swift-mutation-testing@swift-mutation-testing
```

Run `/reload-plugins` or start a new session, then ask Claude in a Swift project something like *"how good are the tests in this package?"*.

To install the plugin for everyone who works on a project, add `--scope project` to both commands. That records the plugin in the project's `.claude/settings.json`.

### Updating the plugin

The plugin has no pinned version: it follows the repository's commits, so every change to the skill on `main` is a new version. Claude Code auto-updates third-party marketplaces only when you turn it on in `/plugin` → **Marketplaces**. Otherwise, update by hand:

```bash
claude plugin marketplace update swift-mutation-testing
claude plugin update swift-mutation-testing@swift-mutation-testing
```

The skill describes the CLI on `main`. When a skill step uses a flag your installed CLI does not have, upgrade the CLI (`brew upgrade swift-mutation-testing`).

### Uninstalling the plugin

```bash
claude plugin uninstall swift-mutation-testing@swift-mutation-testing
claude plugin marketplace remove swift-mutation-testing  # optional
```

---

## Verify the installation

```bash
swift-mutation-testing --version   # print version
swift-mutation-testing --help      # print all available options and flags
swift-mutation-testing init /path/to/project  # generate a starter .swift-mutation-testing.yml
```
