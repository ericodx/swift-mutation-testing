import Foundation

struct TestExecutionStage: Sendable {
    let deps: ExecutionDeps

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        var timedOut: [MutantDescriptor] = []
        let concurrency = context.configuration.build.concurrency

        try await withThrowingTaskGroup(of: Attempt.self) { group in
            var activeTasks = 0
            var iterator = mutants.makeIterator()

            while activeTasks < concurrency, let mutant = iterator.next() {
                group.addTask { try await self.attempt(mutant, in: context) }
                activeTasks += 1
            }

            for try await attempt in group {
                switch attempt {
                case .settled(let result):
                    results.append(result)
                case .timedOut(let mutant):
                    timedOut.append(mutant)
                }

                if let next = iterator.next() {
                    group.addTask { try await self.attempt(next, in: context) }
                }
            }
        }

        for mutant in timedOut {
            results.append(try await runAlone(mutant, in: context))
        }

        return results
    }

    private enum Attempt: Sendable {
        case settled(ExecutionResult)
        case timedOut(MutantDescriptor)
    }

    private func attempt(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) async throws -> Attempt {
        let key = MutantCacheKey.make(for: mutant)

        if let cached = await deps.cacheStore.result(for: key) {
            let killerTestFile = await deps.cacheStore.killerTestFile(for: key)
            let result = ExecutionResult(
                descriptor: mutant, status: cached, testDuration: 0, killerTestFile: killerTestFile
            )
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(descriptor: mutant, status: cached, index: index, total: deps.counter.total))
            return .settled(result)
        }

        let (outcome, launched) = try await measure(mutant, in: context)

        if case .timedOut = outcome {
            return .timedOut(mutant)
        }

        return .settled(
            await recordResult(mutant: mutant, key: key, outcome: outcome, launched: launched, in: context)
        )
    }

    private func runAlone(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        let key = MutantCacheKey.make(for: mutant)
        let (outcome, launched) = try await measure(mutant, in: context)
        return await recordResult(mutant: mutant, key: key, outcome: outcome, launched: launched, in: context)
    }

    private func measure(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) async throws -> (TestRunOutcome, TestLaunchResult) {
        guard let plist = context.artifact.plist else {
            return try await measureSPM(mutant, in: context)
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

        return (outcome, launched)
    }

    private func measureSPM(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) async throws -> (TestRunOutcome, TestLaunchResult) {
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
        return (outcome, launched)
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
                    timeout: configuration.build.timeout,
                    libraries: context.libraries
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
