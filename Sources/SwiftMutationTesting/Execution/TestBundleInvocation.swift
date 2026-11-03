import Foundation

struct TestBundleInvocation: Sendable {

    static let noTestsExitCode: Int32 = 69

    static func reportsNoTests(exitCode: Int32, output: String) -> Bool {
        exitCode == noTestsExitCode || output.contains("Executed 0 tests")
    }

    static func bundleURLs(in sandbox: Sandbox) -> [URL] {
        let products = sandbox.rootURL.appendingPathComponent(".build/out/Products/Debug")
        let candidates =
            (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []

        return
            candidates
            .filter { $0.pathExtension == "xctest" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    let bundleURL: URL
    let framework: TestingFramework

    func requests(
        filter: String?,
        mutantID: String,
        workingDirectory: URL,
        timeout: Double,
        libraries: Set<TestingFramework> = [.xctest, .swiftTesting],
        stoppingAtFirstFailure: Bool = true,
        activationFile: String? = nil,
        reaching: [TestReference]? = nil,
        coverageDirectory: URL? = nil
    ) -> [ProcessRequest] {
        let environment = Self.environment(mutantID: mutantID, activationFile: activationFile)
        let xctest = xctestRequest(
            filter: filter, tests: reaching.map { Self.tests(of: .xctest, in: $0) },
            environment: environment, workingDirectory: workingDirectory, timeout: timeout
        )
        let swiftTesting = swiftTestingRequest(
            filter: filter, tests: reaching.map { Self.tests(of: .swiftTesting, in: $0) },
            environment: environment, workingDirectory: workingDirectory, timeout: timeout,
            collectingCoverage: coverageDirectory != nil
        )

        let ordered: [(TestingFramework, ProcessRequest?)] =
            framework == .xctest
            ? [(.xctest, xctest), (.swiftTesting, swiftTesting)]
            : [(.swiftTesting, swiftTesting), (.xctest, xctest)]

        return ordered.filter { libraries.contains($0.0) }.compactMap { entry in
            guard var request = entry.1 else { return nil }
            if let coverageDirectory {
                request = Self.collecting(request, in: coverageDirectory)
            }
            return stoppingAtFirstFailure ? request.stopping(at: .firstTestFailure) : request
        }
    }

    static func collecting(_ request: ProcessRequest, in directory: URL) -> ProcessRequest {
        let url = directory.appendingPathComponent("coverage-\(UUID().uuidString).log")
        var collecting = request.capturingOutput(at: url)
        collecting.additionalEnvironment[SupportDeclarations.coverageEnvironmentVariable] = url.path
        return collecting
    }

    static func environment(mutantID: String, activationFile: String?) -> [String: String] {
        var environment = ["__SWIFT_MUTATION_TESTING_ACTIVE": mutantID]
        if let activationFile {
            environment[ActivationMarker.environmentVariable] = activationFile
        }
        return environment
    }

    static let coverageEventStreamArguments = [
        "--no-parallel", "--event-stream-output-path", "/dev/fd/2", "--event-stream-version", "0",
    ]

    static func tests(of library: TestingFramework, in reaching: [TestReference]) -> [String] {
        reaching.filter { $0.library == library }.map(\.id)
    }

    static func swiftTestingFilter(for id: String) -> String {
        "^" + NSRegularExpression.escapedPattern(for: id) + "/"
    }

    // MARK: - Private

    private var executableURL: URL {
        bundleURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(bundleURL.deletingPathExtension().lastPathComponent)
    }

    private func xctestRequest(
        filter: String?,
        tests: [String]?,
        environment: [String: String],
        workingDirectory: URL,
        timeout: Double
    ) -> ProcessRequest? {
        var arguments: [String] = []
        if let tests {
            guard !tests.isEmpty else { return nil }
            arguments += ["-XCTest", tests.joined(separator: ",")]
        } else if let filter {
            arguments += ["-XCTest", filter]
        }
        arguments.append(bundleURL.path)

        return ProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["xctest"] + arguments,
            environment: nil,
            additionalEnvironment: environment,
            workingDirectoryURL: workingDirectory,
            timeout: timeout
        )
    }

    private func swiftTestingRequest(
        filter: String?,
        tests: [String]?,
        environment: [String: String],
        workingDirectory: URL,
        timeout: Double,
        collectingCoverage: Bool = false
    ) -> ProcessRequest? {
        var arguments = [
            "--test-bundle-path", executableURL.path,
            executableURL.path,
            "--testing-library", "swift-testing",
        ]
        if let tests {
            guard !tests.isEmpty else { return nil }
            arguments += tests.flatMap { ["--filter", Self.swiftTestingFilter(for: $0)] }
        } else if let filter {
            arguments += ["--filter", filter]
        }
        if collectingCoverage { arguments += Self.coverageEventStreamArguments }

        return ProcessRequest(
            executableURL: URL(fileURLWithPath: DeveloperToolchain.testingHelperPath),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: Uniquing.keepingFirst(
                environment.map { ($0.key, $0.value) } + [
                    ("DYLD_FRAMEWORK_PATH", DeveloperToolchain.frameworksPath),
                    ("DYLD_LIBRARY_PATH", DeveloperToolchain.librariesPath),
                ]
            ),
            workingDirectoryURL: workingDirectory,
            timeout: timeout
        )
    }
}

enum DeveloperToolchain {

    nonisolated(unsafe) static var developerPath: String = resolveDeveloperPath()

    static func resolveDeveloperPath(
        running executable: URL = URL(fileURLWithPath: "/usr/bin/xcode-select"),
        arguments: [String] = ["-p"]
    ) -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
