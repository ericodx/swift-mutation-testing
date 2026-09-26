import Foundation

struct TestBundleInvocation: Sendable {

    static let noTestsExitCode: Int32 = 69

    static func reportsNoTests(exitCode: Int32, output: String) -> Bool {
        exitCode == noTestsExitCode || output.contains("Executed 0 tests")
    }

    static func bundleURL(in sandbox: Sandbox) -> URL? {
        let products = sandbox.rootURL.appendingPathComponent(".build/out/Products/Debug")
        let candidates =
            (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []

        return candidates.first { $0.pathExtension == "xctest" }
    }

    let bundleURL: URL
    let framework: TestingFramework

    func requests(
        filter: String?,
        mutantID: String,
        workingDirectory: URL,
        timeout: Double,
        libraries: Set<TestingFramework> = [.xctest, .swiftTesting]
    ) -> [ProcessRequest] {
        let xctest = xctestRequest(
            filter: filter, mutantID: mutantID, workingDirectory: workingDirectory, timeout: timeout
        )
        let swiftTesting = swiftTestingRequest(
            filter: filter, mutantID: mutantID, workingDirectory: workingDirectory, timeout: timeout
        )

        let ordered: [(TestingFramework, ProcessRequest)] =
            framework == .xctest
            ? [(.xctest, xctest), (.swiftTesting, swiftTesting)]
            : [(.swiftTesting, swiftTesting), (.xctest, xctest)]

        return ordered.filter { libraries.contains($0.0) }.map(\.1)
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

enum DeveloperToolchain {

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
