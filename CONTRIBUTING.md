# Contributing to Swift Mutation Testing

Thank you for your interest in contributing to **SwiftMutationTesting**.

Swift Mutation Testing is a Swift CLI that runs mutation testing on Xcode projects and workspaces and on Swift packages, with XCTest or Swift Testing. It discovers the mutants, writes them into a sandbox copy of the project, builds it, runs the tests against each mutant and reports the result: discovery → sandbox → build → test → report.

For an overview of the project goals and scope, see the [README](README.md).

---

## Code of Conduct

Be respectful, professional, and constructive in all interactions.
This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

---

## Technical Principles

SwiftMutationTesting follows a strict set of technical principles:

- The original project is **never modified** — all mutations happen inside an isolated sandbox
- The schema is built **once** for all schematizable mutants — `xcodebuild build-for-testing` for Xcode, `swift build --build-tests` for packages
- No mutant results are **lost or duplicated**
- Mutant **positions (file, line, column) are accurate** in all reported results
- A cancelled task never leaves a **simulator slot permanently acquired** from the pool
- Every schematized file **declares its own** support block, `@usableFromInline internal` and named after the file (`__swiftMutationTestingID_<hash>`), and nothing else in the sandbox declares it
- **No dependency beyond swift-syntax** — CryptoKit and Foundation are Apple frameworks; no other package is permitted
- Full compatibility with **Swift 6 Strict Concurrency**
- Pipeline stages are **stateless pure transformations** — no shared mutable state between them

Changes that violate these principles will not be accepted, even if they pass tests.

---

## AI-Assisted Contributions

AI-assisted contributions are welcome.

When using tools such as GitHub Copilot or other LLMs:

- Treat AI as an **assistant**, not an authority
- Ensure all generated code follows the same standards as human-written code
- Do not introduce speculative or inferred behavior

Follow the same code review standards regardless of how the code was written.

---

## Pull Requests

All Pull Requests must:

- Follow the repository PR template
- Be focused on a single concern
- Reference an existing issue when applicable
- Respect the technical principles described above

AI-generated changes are reviewed under the same criteria as human-written code.

---

## Workflow

1. Open an issue describing the problem or proposal
2. Wait for maintainer feedback
3. Implement the change in a focused branch
4. Open a Pull Request referencing the issue

Unapproved structural changes may be closed without review.

### Mutation operators

A new operator enters the registry as `experimental` and is promoted to `default` or `conservative` only with
campaign data, by the criteria in [Docs/OPERATORS.md](Docs/OPERATORS.md): run the campaign over the corpus,
review the sampled survivors, and let the aggregation assign the tier. An operator whose numbers fall
below its tier's bar is demoted the same way, and the change is recorded there with its reason.

---

## Testing

For local build, test, fixture, and pre-commit setup, see
[Building for Contributors](Docs/BUILDING.md).

- Unit tests are mandatory for all new functionality
- Use Swift Testing (`@Suite`, `@Test`) with Given/When/Then naming
- Use a mock conforming to `ProcessLaunching` — never invoke real `xcodebuild`, `xcrun simctl`, or `xcresulttool` in unit tests
- Use `FileHelpers` for any test that touches the filesystem (temp directories only)
- Integration tests must use a real fixture project from `Fixtures/` and be tagged `.integration`
- Tests must be **deterministic and isolated** — same input always produces the same output
- Target code coverage: **90%+**

---

## Communication

All communication happens publicly via [GitHub Issues and Discussions](https://github.com/ericodx/swift-mutation-testing/discussions).
Private contact is discouraged.

---

## License

By contributing, you agree that your contributions are licensed under the [MIT](./LICENSE).
