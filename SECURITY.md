# Security Policy

## Supported Versions

Swift Mutation Testing is currently under active development.

Only the **latest release** is supported with security updates.

Pre-release versions (`0.x`) do not carry stability or security guarantees.

| Version | Supported          |
|---------|--------------------|
| 1.x.x   | ✓ Supported        |

---

## Reporting a Vulnerability

If you discover a security vulnerability in Swift Mutation Testing, please **do not open a public issue**.

Instead, report it privately by opening a **GitHub Security Advisory**:

1. Go to the repository on GitHub
2. Click on **Security**
3. Select **Report a vulnerability**
4. Provide:
   - A clear description of the issue
   - Steps to reproduce (if applicable)
   - Potential impact

All reports will be reviewed promptly.

---

## Scope

This security policy applies to:

- The Swift Mutation Testing CLI (`swift-mutation-testing`)
- Distribution artifacts
- Configuration handling (`.swift-mutation-testing.yml`)
- `RunnerInput` parsing and sandbox isolation

It does **not** cover:

- Third-party dependencies beyond their own advisories
- Misuse of the tool outside documented behavior

---

## Disclosure Process

- Vulnerabilities are triaged privately
- Fixes are developed and tested
- A release is published with appropriate notes
- Credit is given when requested

We aim to balance transparency with user safety.

---

## Responsible Disclosure

We kindly ask reporters to allow reasonable time for investigation and fixes before any public disclosure.

Thank you for helping keep Swift Mutation Testing secure.
