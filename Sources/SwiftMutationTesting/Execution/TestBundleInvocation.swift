import Foundation

/// How to run a package's compiled test bundle without going through `swift test`.
///
/// `swift test` takes a lock on `.build`, so workers sharing a sandbox queue behind each other and
/// the wait counts against each mutant's timeout — which is why SPM runs were sequential (issue
/// #77). The bundle SwiftPM already built can be run directly instead: no lock is taken, the build
/// still happens exactly once, and workers are genuinely independent.
///
/// The two testing frameworks are launched differently. XCTest bundles are run by `xctest`, which
/// takes the bundle. Swift Testing is run by SwiftPM's own helper, which dlopens the executable
/// inside the bundle and therefore needs the developer directory on its library paths — the
/// environment `swift test` would otherwise have set up.
struct TestBundleInvocation: Sendable {

    /// What SwiftPM's helper reports when the bundle holds no tests for the library it was asked
    /// to run — `EX_UNAVAILABLE`, returned alongside a passing "0 tests" run. A package that uses
    /// only one testing library produces it for the other, so it means "nothing to run here", not
    /// a failure.
    static let noTestsExitCode: Int32 = 69

    /// The `.xctest` bundle for a package built in `sandbox`, or `nil` when none was produced.
    static func bundleURL(in sandbox: Sandbox) -> URL? {
        let products = sandbox.rootURL.appendingPathComponent(".build/out/Products/Debug")
        let candidates =
            (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []

        return candidates.first { $0.pathExtension == "xctest" }
    }

    let bundleURL: URL
    let framework: TestingFramework

    /// The processes that run the bundle, selecting `filter` when one is given.
    ///
    /// Both testing libraries are run, in the order `swift test` runs them, because that is what
    /// `swift test` did: a package may hold XCTest classes and Swift Testing functions at once, and
    /// running only the configured one would silently skip the other's tests — reporting mutants as
    /// survivors because nothing was there to catch them. `testingFramework` chooses which runs
    /// first, not which runs.
    ///
    /// `filter` is a test name for XCTest (`SuiteName/testName`) and a regular expression for Swift
    /// Testing, matching what `swift test --filter` accepted.
    func requests(
        filter: String?,
        mutantID: String,
        workingDirectory: URL,
        timeout: Double
    ) -> [ProcessRequest] {
        let xctest = xctestRequest(
            filter: filter, mutantID: mutantID, workingDirectory: workingDirectory, timeout: timeout
        )
        let swiftTesting = swiftTestingRequest(
            filter: filter, mutantID: mutantID, workingDirectory: workingDirectory, timeout: timeout
        )

        return framework == .xctest ? [xctest, swiftTesting] : [swiftTesting, xctest]
    }

    // MARK: - Private

    private var executableURL: URL {
        bundleURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(bundleURL.deletingPathExtension().lastPathComponent)
    }

    private func xctestRequest(
        filter: String?,
        mutantID: String,
        workingDirectory: URL,
        timeout: Double
    ) -> ProcessRequest {
        var arguments: [String] = []
        if let filter { arguments += ["-XCTest", filter] }
        arguments.append(bundleURL.path)

        return ProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["xctest"] + arguments,
            environment: nil,
            additionalEnvironment: ["__SWIFT_MUTATION_TESTING_ACTIVE": mutantID],
            workingDirectoryURL: workingDirectory,
            timeout: timeout
        )
    }

    private func swiftTestingRequest(
        filter: String?,
        mutantID: String,
        workingDirectory: URL,
        timeout: Double
    ) -> ProcessRequest {
        var arguments = [
            "--test-bundle-path", executableURL.path,
            executableURL.path,
            "--testing-library", "swift-testing",
        ]
        if let filter { arguments += ["--filter", filter] }

        return ProcessRequest(
            executableURL: URL(fileURLWithPath: DeveloperToolchain.testingHelperPath),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: [
                "__SWIFT_MUTATION_TESTING_ACTIVE": mutantID,
                "DYLD_FRAMEWORK_PATH": DeveloperToolchain.frameworksPath,
                "DYLD_LIBRARY_PATH": DeveloperToolchain.librariesPath,
            ],
            workingDirectoryURL: workingDirectory,
            timeout: timeout
        )
    }
}

/// Paths inside the selected Xcode that running a test bundle by hand needs, and that `swift test`
/// would otherwise supply.
enum DeveloperToolchain {

    /// Resolved once: `xcode-select` does not change under a running process.
    nonisolated(unsafe) static var developerPath: String = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var testingHelperPath: String {
        "\(developerPath)/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
    }

    static var frameworksPath: String {
        "\(developerPath)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    }

    static var librariesPath: String {
        "\(developerPath)/Platforms/MacOSX.platform/Developer/usr/lib"
    }
}
