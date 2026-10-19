import Foundation

struct BaselineProbe: Sendable {
    let configuration: RunnerConfiguration
    let launcher: any ProcessLaunching

    func probeTestBundles(in sandbox: Sandbox) async throws -> (bundles: [TestBundle], filter: String?) {
        let selection = TestTargetSelection.make(
            target: configuration.build.testTarget, bundleURLs: TestBundleInvocation.bundleURLs(in: sandbox)
        )
        let urls = selection.bundleURLs

        guard !urls.isEmpty else {
            try await validateBaseline(running: swiftTestRequest(in: sandbox))
            return ([], selection.filter)
        }

        var bundles: [TestBundle] = []

        for url in urls {
            let libraries = try await probeLibraries(of: url, in: sandbox, filter: selection.filter)
            if !libraries.isEmpty {
                bundles.append(TestBundle(url: url, libraries: libraries))
            }
        }

        let probed = bundles.isEmpty ? urls.map { TestBundle(url: $0, libraries: TestBundle.allLibraries) } : bundles
        return (probed, selection.filter)
    }

    private func probeLibraries(
        of bundleURL: URL,
        in sandbox: Sandbox,
        filter: String?
    ) async throws -> Set<TestingFramework> {
        let invocation = TestBundleInvocation(bundleURL: bundleURL, framework: configuration.build.testingFramework)
        var present: Set<TestingFramework> = []

        for library in TestBundle.allLibraries {
            let requests = invocation.requests(
                filter: filter,
                mutantID: "",
                workingDirectory: sandbox.rootURL,
                timeout: configuration.build.timeout,
                libraries: [library],
                stoppingAtFirstFailure: false
            )

            for request in requests {
                let captured = try await launcher.launchCapturing(request)

                guard !TestBundleInvocation.reportsNoTests(exitCode: captured.exitCode, output: captured.output)
                else { continue }

                try requireBaselineToPass(exitCode: captured.exitCode, output: captured.output)
                present.insert(library)
            }
        }

        return present
    }

    private func swiftTestRequest(in sandbox: Sandbox) -> ProcessRequest {
        ToolRequests.swiftTest(
            in: sandbox,
            filter: configuration.build.testTarget,
            environment: ["__SWIFT_MUTATION_TESTING_ACTIVE": ""],
            timeout: configuration.build.timeout
        )
    }

    private func validateBaseline(running request: ProcessRequest) async throws {
        let captured = try await launcher.launchCapturing(request)
        try requireBaselineToPass(exitCode: captured.exitCode, output: captured.output)
    }

    func requirePassing(_ outcome: TestRunOutcome, output: String) throws {
        switch outcome {
        case .testsSucceeded:
            return

        case .timedOut:
            throw BaselineError.didNotFinish(seconds: configuration.build.timeout)

        case .testsFailed, .crashed, .unviable, .buildFailed:
            MutantLogWriter(directory: configuration.reporting.keepLogsPath)?.write(baselineOutput: output)
            var failing = TestOutputParser().failingTests(in: output)
            if failing.isEmpty, case .testsFailed(let name) = outcome {
                failing = [name]
            }
            throw failing.isEmpty
                ? BaselineError.runFailed(output: output)
                : BaselineError.testsFailed(tests: failing)
        }
    }

    private func requireBaselineToPass(exitCode: Int32, output: String) throws {
        try requirePassing(SPMResultParser().parse(exitCode: exitCode, output: output), output: output)
    }
}
