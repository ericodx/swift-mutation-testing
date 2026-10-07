import Foundation

struct TestExecutionStage: Sendable {
    let deps: ExecutionDeps

    static let loadedTimeoutFactor: Double = 2
    static let retryWorkerShare = 4

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult] {
        let timeout = context.configuration.build.timeout
        let concurrency = context.configuration.build.concurrency
        var results: [ExecutionResult] = []
        var timedOut: [MutantDescriptor] = []
        var killedUnactivated: [MutantDescriptor] = []

        try await forEach(
            mutants, concurrency: concurrency,
            run: { mutant in
                try await self.attempt(mutant, in: context, timeout: timeout * Self.loadedTimeoutFactor)
            },
            collect: { attempt in
                switch attempt {
                case .settled(let result):
                    results.append(result)
                case .timedOut(let mutant):
                    timedOut.append(mutant)
                case .killedUnactivated(let mutant):
                    killedUnactivated.append(mutant)
                }
            }
        )

        try await forEach(
            timedOut, concurrency: max(1, concurrency / Self.retryWorkerShare),
            run: { mutant in try await self.runAgain(mutant, in: context, timeout: timeout) },
            collect: { result in results.append(result) }
        )

        try await forEach(
            killedUnactivated, concurrency: 1,
            run: { mutant in try await self.runAgain(mutant, in: context, timeout: timeout) },
            collect: { result in results.append(result) }
        )

        return results
    }

    private func forEach<Element, Outcome: Sendable>(
        _ elements: [Element],
        concurrency: Int,
        run: @escaping @Sendable (Element) async throws -> Outcome,
        collect: (Outcome) -> Void
    ) async throws where Element: Sendable {
        try await withThrowingTaskGroup(of: Outcome.self) { group in
            var activeTasks = 0
            var iterator = elements.makeIterator()

            while activeTasks < concurrency, let element = iterator.next() {
                group.addTask { try await run(element) }
                activeTasks += 1
            }

            for try await outcome in group {
                collect(outcome)

                if let next = iterator.next() {
                    group.addTask { try await run(next) }
                }
            }
        }
    }

    private enum Attempt: Sendable {
        case settled(ExecutionResult)
        case timedOut(MutantDescriptor)
        case killedUnactivated(MutantDescriptor)
    }

    private func attempt(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext,
        timeout: Double
    ) async throws -> Attempt {
        if let cached = await recorder(in: context).cached(mutant) {
            return .settled(cached)
        }

        let (outcome, launched) = try await measure(mutant, in: context, timeout: timeout)

        if case .timedOut = outcome {
            return .timedOut(mutant)
        }

        if outcome.asExecutionStatus.isKill, !launched.activated {
            return .killedUnactivated(mutant)
        }

        return .settled(
            await recordResult(mutant: mutant, outcome: outcome, launched: launched, in: context)
        )
    }

    private func runAgain(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext,
        timeout: Double
    ) async throws -> ExecutionResult {
        let (outcome, launched) = try await measure(mutant, in: context, timeout: timeout)
        return await recordResult(mutant: mutant, outcome: outcome, launched: launched, in: context)
    }

    private func measure(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext,
        timeout: Double
    ) async throws -> (TestRunOutcome, TestLaunchResult) {
        guard let plist = context.artifact.plist else {
            return try await measureSPM(mutant, in: context, timeout: timeout)
        }

        let marker = ActivationMarker(for: mutant.id, in: context.sandbox)
        let plistData = plist.activating(mutant.id, activationFile: marker.path)
        let slot = try await context.pool.acquire()
        var launched: TestLaunchResult
        do {
            launched = try await launch(plistData: plistData, slot: slot, in: context, timeout: timeout)
        } catch {
            await context.pool.release(slot)
            throw error
        }

        await context.pool.release(slot)
        launched.activated = marker.wasWritten()

        let outcome = try await ResultParser(launcher: deps.launcher).parse(
            exitCode: launched.exitCode,
            output: launched.output,
            xcresultPath: launched.xcresultPath,
            timeout: timeout
        )
        try? FileManager.default.removeItem(atPath: launched.xcresultPath)

        return (outcome, launched)
    }

    private func measureSPM(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext,
        timeout: Double
    ) async throws -> (TestRunOutcome, TestLaunchResult) {
        let slot = try await context.pool.acquire()

        do {
            let measured = try await measureSPMTargetedFirst(mutant, in: context, timeout: timeout)
            await context.pool.release(slot)
            return measured
        } catch {
            await context.pool.release(slot)
            throw error
        }
    }

    private func measureSPMTargetedFirst(
        _ mutant: MutantDescriptor,
        in context: TestExecutionContext,
        timeout: Double
    ) async throws -> (TestRunOutcome, TestLaunchResult) {
        var activated = false

        if !context.configuration.build.reproducing,
            let suite = TargetedSuites.suite(for: mutant.filePath, among: context.targetedSuites)
        {
            let marker = ActivationMarker(for: mutant.id, in: context.sandbox)
            var targeted = try await launchSPM(
                mutant: mutant, in: context, timeout: timeout,
                run: SPMRun(filter: suite.name, bundles: context.bundles(declaring: suite), activationFile: marker.path)
            )
            let outcome = SPMResultParser().parse(exitCode: targeted.exitCode, output: targeted.output)
            activated = marker.wasWritten()
            targeted.activated = activated

            if outcome.isKill { return (outcome, targeted) }
        }

        let marker = ActivationMarker(for: mutant.id, in: context.sandbox)
        var launched = try await launchSPM(
            mutant: mutant, in: context, timeout: timeout,
            run: SPMRun(
                filter: context.testFilter, bundles: context.bundles, activationFile: marker.path
            )
        )
        let outcome = SPMResultParser().parse(exitCode: launched.exitCode, output: launched.output)
        launched.activated = marker.wasWritten() || activated
        return (outcome, launched)
    }

    private func recordResult(
        mutant: MutantDescriptor,
        outcome: TestRunOutcome,
        launched: TestLaunchResult,
        in context: TestExecutionContext
    ) async -> ExecutionResult {
        await recorder(in: context).record(
            mutant, status: Self.classify(outcome.asExecutionStatus, activated: launched.activated),
            duration: launched.duration, output: launched.output, activated: launched.activated
        )
    }

    private func recorder(in context: TestExecutionContext) -> ResultRecorder {
        ResultRecorder(deps: deps, keepLogsPath: context.configuration.reporting.keepLogsPath)
    }

    static func classify(_ status: ExecutionStatus, activated: Bool) -> ExecutionStatus {
        status == .survived && !activated ? .noCoverage : status
    }

    private struct SPMRun {
        let filter: String?
        let bundles: [TestBundle]
        let activationFile: String
    }

    private func launchSPM(
        mutant: MutantDescriptor,
        in context: TestExecutionContext,
        timeout: Double,
        run: SPMRun
    ) async throws -> TestLaunchResult {
        let start = Date()
        let captured = try await self.run(
            spmRequests(mutant: mutant, in: context, timeout: timeout, run: run),
            deadline: start.addingTimeInterval(timeout)
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
        in context: TestExecutionContext,
        timeout: Double,
        run: SPMRun
    ) -> [ProcessRequest] {
        let configuration = context.configuration

        guard run.bundles.isEmpty else {
            return run.bundles.flatMap { bundle in
                TestBundleInvocation(bundleURL: bundle.url, framework: configuration.build.testingFramework)
                    .requests(
                        filter: run.filter,
                        mutantID: mutant.id,
                        workingDirectory: context.sandbox.rootURL,
                        timeout: timeout,
                        libraries: bundle.libraries,
                        stoppingAtFirstFailure: !configuration.build.reproducing,
                        activationFile: run.activationFile
                    )
            }
        }

        let request = ToolRequests.swiftTest(
            in: context.sandbox,
            filter: run.filter,
            environment: TestBundleInvocation.environment(mutantID: mutant.id, activationFile: run.activationFile),
            timeout: timeout
        )
        return [configuration.build.reproducing ? request : request.stopping(at: .firstTestFailure)]
    }

    private func launch(
        plistData: Data,
        slot: SimulatorSlot,
        in context: TestExecutionContext,
        timeout: Double
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
            ToolRequests.xcodebuild(arguments, in: context.sandbox, timeout: timeout)
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }
}
