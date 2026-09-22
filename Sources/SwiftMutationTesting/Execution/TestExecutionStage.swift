import Foundation

struct TestExecutionStage: Sendable {
    let deps: ExecutionDeps

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        let concurrency = context.configuration.build.concurrency

        try await withThrowingTaskGroup(of: ExecutionResult.self) { group in
            var activeTasks = 0
            var iterator = mutants.makeIterator()

            while activeTasks < concurrency, let mutant = iterator.next() {
                let key = MutantCacheKey.make(for: mutant)
                group.addTask { try await self.run(mutant: mutant, key: key, in: context) }
                activeTasks += 1
            }

            for try await result in group {
                results.append(result)
                if let next = iterator.next() {
                    let key = MutantCacheKey.make(for: next)
                    group.addTask { try await self.run(mutant: next, key: key, in: context) }
                }
            }
        }

        return results
    }

    private func run(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        if let cached = await deps.cacheStore.result(for: key) {
            let killerTestFile = await deps.cacheStore.killerTestFile(for: key)
            let result = ExecutionResult(
                descriptor: mutant, status: cached, testDuration: 0, killerTestFile: killerTestFile
            )
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(descriptor: mutant, status: cached, index: index, total: deps.counter.total))
            return result
        }

        guard let plist = context.artifact.plist else {
            return try await runSPM(mutant: mutant, key: key, in: context)
        }

        let plistData = plist.activating(mutant.id)
        let slot = try await context.pool.acquire()
        let launched: TestLaunchResult
        do {
            launched = try await launch(plistData: plistData, slot: slot, in: context)
        } catch {
            await context.pool.release(slot)
            throw error
        }

        await context.pool.release(slot)

        let outcome = try await ResultParser(launcher: deps.launcher).parse(
            exitCode: launched.exitCode,
            output: launched.output,
            xcresultPath: launched.xcresultPath,
            timeout: context.configuration.build.timeout
        )
        try? FileManager.default.removeItem(atPath: launched.xcresultPath)

        return await recordResult(mutant: mutant, key: key, outcome: outcome, launched: launched, in: context)
    }

    private func runSPM(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        let slot = try await context.pool.acquire()
        let launched: TestLaunchResult
        do {
            launched = try await launchSPM(mutant: mutant, in: context)
        } catch {
            await context.pool.release(slot)
            throw error
        }

        let outcome = SPMResultParser().parse(exitCode: launched.exitCode, output: launched.output)
        await context.pool.release(slot)
        return await recordResult(mutant: mutant, key: key, outcome: outcome, launched: launched, in: context)
    }

    private func recordResult(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        outcome: TestRunOutcome,
        launched: TestLaunchResult,
        in context: TestExecutionContext
    ) async -> ExecutionResult {
        let status = outcome.asExecutionStatus
        let duration = launched.duration

        MutantLogWriter(directory: context.configuration.reporting.keepLogsPath)?
            .write(mutant: mutant, status: status, duration: duration, output: launched.output)
        let killerTestFile = resolveKillerTestFile(status: status)
        let result = ExecutionResult(
            descriptor: mutant, status: status, testDuration: duration,
            killerTestFile: killerTestFile
        )
        await deps.cacheStore.store(status: status, for: key, killerTestFile: killerTestFile)
        let index = await deps.counter.increment()
        await deps.reporter.report(
            .mutantFinished(
                descriptor: mutant, status: status,
                index: index, total: deps.counter.total
            )
        )
        return result
    }

    private func resolveKillerTestFile(status: ExecutionStatus) -> String? {
        guard case .killed(let testName) = status else { return nil }
        return deps.killerTestFileResolver.resolve(testName: testName)
    }

    /// Runs the compiled test bundle rather than `swift test`, so that workers sharing a sandbox do
    /// not queue behind SwiftPM's lock on `.build` (issue #77). Falls back to `swift test` when no
    /// bundle can be found, which keeps a run working rather than failing on an unfamiliar layout.
    private func launchSPM(
        mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        let start = Date()
        let captured = try await run(
            spmRequests(mutant: mutant, in: context),
            deadline: start.addingTimeInterval(context.configuration.build.timeout)
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: "",
            duration: Date().timeIntervalSince(start)
        )
    }

    /// Runs each request in turn, stopping at the first that does not succeed.
    ///
    /// The requests share one deadline, since between them they are the single test run a mutant is
    /// given — running both testing libraries must not buy a mutant twice the configured timeout.
    private func run(
        _ requests: [ProcessRequest],
        deadline: Date
    ) async throws -> (exitCode: Int32, output: String) {
        var combined = ""

        for request in requests {
            let remaining = deadline.timeIntervalSinceNow

            guard remaining > 0 else {
                return (exitCode: SPMResultParser.timedOutExitCode, output: combined)
            }

            let captured = try await deps.launcher.launchCapturing(request.withTimeout(remaining))

            // The bundle holds no tests for this library, so there is nothing to report from it.
            guard captured.exitCode != TestBundleInvocation.noTestsExitCode else { continue }

            combined += combined.isEmpty ? captured.output : "\n" + captured.output

            guard captured.exitCode == 0 else { return (exitCode: captured.exitCode, output: combined) }
        }

        return (exitCode: 0, output: combined)
    }

    private func spmRequests(
        mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) -> [ProcessRequest] {
        let configuration = context.configuration

        if let bundleURL = TestBundleInvocation.bundleURL(in: context.sandbox) {
            return TestBundleInvocation(bundleURL: bundleURL, framework: configuration.build.testingFramework)
                .requests(
                    filter: configuration.build.testTarget,
                    mutantID: mutant.id,
                    workingDirectory: context.sandbox.rootURL,
                    timeout: configuration.build.timeout
                )
        }

        var arguments = ["test", "--skip-build"]
        if let testTarget = configuration.build.testTarget {
            arguments += ["--filter", testTarget]
        }

        return [
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: ["__SWIFT_MUTATION_TESTING_ACTIVE": mutant.id],
                workingDirectoryURL: context.sandbox.rootURL,
                timeout: configuration.build.timeout
            )
        ]
    }

    private func launch(
        plistData: Data,
        slot: SimulatorSlot,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        let baseURL =
            context.artifact.xctestrunURL?.deletingLastPathComponent()
            ?? context.sandbox.rootURL
        let xctestrunURL = baseURL.appendingPathComponent("\(UUID().uuidString).xctestrun")
        let xcresultPath = context.sandbox.rootURL
            .appendingPathComponent("\(UUID().uuidString).xcresult").path

        defer { try? FileManager.default.removeItem(at: xctestrunURL) }

        try plistData.write(to: xctestrunURL)

        var arguments = [
            "test-without-building",
            "-xctestrun", xctestrunURL.path,
            "-destination", slot.destination,
            "-resultBundlePath", xcresultPath,
            "-derivedDataPath", context.artifact.derivedDataPath,
        ]

        if let testTarget = context.configuration.build.testTarget {
            arguments += ["-only-testing", testTarget]
        }

        let start = Date()
        let captured = try await deps.launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: context.sandbox.rootURL,
                timeout: context.configuration.build.timeout
            )
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }
}
