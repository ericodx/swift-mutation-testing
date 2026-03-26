# Installation

## Requirements

- macOS 15 or later
- Xcode 16 or later (for building from source)
- Swift 6.2 or later (for building from source)

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
# swift-mutation-testing 0.1.0
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

## Verify the installation

```bash
swift-mutation-testing --version   # print version
swift-mutation-testing --help      # print all available options and flags
swift-mutation-testing /path/to/project init  # generate a starter .swift-mutation-testing.yml
```
