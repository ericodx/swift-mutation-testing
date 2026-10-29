import Foundation

extension IncompatibleMutantExecutor {
    func runXcode(
        _ mutants: [MutantDescriptor],
        scheme: String,
        configuration: RunnerConfiguration,
        pool: SimulatorPool,
        reusing sandbox: Sandbox?
    ) async throws -> [ExecutionResult] {
        guard !configuration.build.reproducing else {
            return try await PhaseTimings.measure(.incompatible, in: deps.timings) {
                try await runXcodeCold(mutants, scheme: scheme, configuration: configuration, pool: pool)
            }
        }

        let (unviable, viable) = await separateViable(mutants, configuration: configuration)
        var results = unviable

        if !viable.isEmpty {
            let width = Self.xcodeWidth(
                concurrency: configuration.build.concurrency, poolSize: pool.size, mutantCount: viable.count
            )
            let warmup = XcodeWarmup(reused: sandbox, scheme: scheme, configuration: configuration, pool: pool)
            let warm = try await runOnWarmSandboxes(viable, width: width, configuration: configuration) {
                try await warmXcodeWorker(index: $0, queue: $1, warmup: warmup)
            }
            for (index, result) in warm {
                results[index] = result
            }
        }

        return mutants.indices.compactMap { results[$0] }
    }

    struct XcodeWorker: Sendable {
        let sandbox: Sandbox
        let slot: SimulatorSlot
        let scheme: String
    }

    private struct XcodeWarmup: Sendable {
        let reused: Sandbox?
        let scheme: String
        let configuration: RunnerConfiguration
        let pool: SimulatorPool
    }

    private func warmXcodeWorker(index: Int, queue: MutantQueue, warmup: XcodeWarmup) async throws -> WarmOutcome {
        let slot = try await warmup.pool.acquire()
        do {
            let outcome = try await warmXcodeSandbox(index: index, slot: slot, queue: queue, warmup: warmup)
            await warmup.pool.release(slot)
            return outcome
        } catch {
            await warmup.pool.release(slot)
            throw error
        }
    }

    private func warmXcodeSandbox(
        index: Int, slot: SimulatorSlot, queue: MutantQueue, warmup: XcodeWarmup
    ) async throws -> WarmOutcome {
        let configuration = warmup.configuration
        let reusing = index == 0 && warmup.reused != nil
        let sandbox: Sandbox
        if reusing, let reused = warmup.reused {
            sandbox = reused
        } else {
            sandbox = try await sandboxFactory.createClean(
                projectPath: configuration.projectPath, disablingSwiftLint: true
            )
        }
        defer {
            if !reusing { sandbox.release(keepingFor: nil) }
        }

        let build = try await deps.launcher.launchCapturing(
            ToolRequests.buildForTesting(
                in: sandbox, scheme: warmup.scheme, destination: slot.destination,
                arguments: configuration.build.xcodeArguments,
                timeout: configuration.build.buildTimeout
            )
        )
        guard build.exitCode == 0 else { return WarmOutcome(slot: index, build: build, readyAt: nil, results: []) }

        let readyAt = Date()
        let worker = XcodeWorker(sandbox: sandbox, slot: slot, scheme: warmup.scheme)
        let results = try await drain(queue) { warm in
            try await runWarm(warm, on: worker, configuration: configuration)
        }
        return WarmOutcome(slot: index, build: build, readyAt: readyAt, results: results)
    }

    private func runWarm(
        _ warm: WarmMutant, on worker: XcodeWorker, configuration: RunnerConfiguration
    ) async throws -> ExecutionResult {
        let mutant = warm.mutant
        let projectRoot = URL(fileURLWithPath: configuration.projectPath).resolvingSymlinksInPath().path
        let originalPath = URL(fileURLWithPath: mutant.filePath).resolvingSymlinksInPath().path
        guard originalPath.hasPrefix(projectRoot + "/") else {
            return await storeAndReport(
                mutant: mutant, sandbox: nil, keepLogsPath: configuration.reporting.keepLogsPath,
                buildOutput: Self.outsideProjectMessage
            )
        }
        let sandboxPath =
            worker.sandbox.rootURL.resolvingSymlinksInPath().path + originalPath.dropFirst(projectRoot.count)

        do {
            let result = try await buildAndTestWarm(
                warm, at: sandboxPath, on: worker, configuration: configuration
            )
            try SandboxLink.restore(at: sandboxPath, to: originalPath)
            try? removeResultBundles(in: worker.sandbox)
            return result
        } catch {
            try? SandboxLink.restore(at: sandboxPath, to: originalPath)
            try? removeResultBundles(in: worker.sandbox)
            throw error
        }
    }

    private func buildAndTestWarm(
        _ warm: WarmMutant, at sandboxPath: String, on worker: XcodeWorker,
        configuration: RunnerConfiguration
    ) async throws -> ExecutionResult {
        let mutant = warm.mutant
        let content = warm.content

        if let instrumented = ActivationInstrumenter(importStyle: importStyle).instrument(mutant) {
            let attempt = XcodeAttempt(
                mutant: mutant, content: instrumented, measured: true, scheme: worker.scheme,
                configuration: configuration
            )
            let run = XcodeRun(attempt: attempt, slot: worker.slot, sandbox: worker.sandbox)
            try write(instrumented, to: sandboxPath)
            var verdict = try await buildAndTestXcode(run)
            if verdict.isUnactivatedKill {
                verdict = try await testXcode(run, start: Date())
            }
            if !verdict.buildFailed {
                return await record(verdict, mutant: mutant, configuration: configuration)
            }
        }

        let attempt = XcodeAttempt(
            mutant: mutant, content: content, measured: false, scheme: worker.scheme, configuration: configuration
        )
        try write(content, to: sandboxPath)
        let verdict = try await buildAndTestXcode(
            XcodeRun(attempt: attempt, slot: worker.slot, sandbox: worker.sandbox)
        )
        return await record(verdict, mutant: mutant, configuration: configuration)
    }

    private func write(_ content: String, to path: String) throws {
        try? FileManager.default.removeItem(atPath: path)
        try LintSuppression.wrapping(content).write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func removeResultBundles(in sandbox: Sandbox) throws {
        let root = sandbox.rootURL
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) where name.hasSuffix(".xcresult") {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }

    static func xcodeWidth(concurrency: Int, poolSize: Int, mutantCount: Int) -> Int {
        max(1, min(concurrency / warmSandboxShare, poolSize, mutantCount))
    }

    func runXcodeCold(
        _ mutants: [MutantDescriptor],
        scheme: String,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        guard !mutants.isEmpty else { return [] }

        let width = Self.xcodeWidth(
            concurrency: configuration.build.concurrency, poolSize: pool.size, mutantCount: mutants.count
        )

        let runOne: @Sendable (Int) async throws -> (Int, ExecutionResult) = { index in
            (index, try await run(mutant: mutants[index], scheme: scheme, configuration: configuration, pool: pool))
        }

        return try await withThrowingTaskGroup(of: (Int, ExecutionResult).self) { group in
            var next = 0
            var finished: [(Int, ExecutionResult)] = []

            while next < width {
                let index = next
                group.addTask { try await runOne(index) }
                next += 1
            }

            while let done = try await group.next() {
                finished.append(done)
                guard next < mutants.count else { continue }
                let index = next
                group.addTask { try await runOne(index) }
                next += 1
            }

            return finished.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func run(
        mutant: MutantDescriptor,
        scheme: String,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> ExecutionResult {
        guard let content = mutant.mutatedSourceContent else {
            return await storeAndReport(
                mutant: mutant, sandbox: nil,
                keepLogsPath: configuration.reporting.keepLogsPath,
                buildOutput: "The mutation could not be applied to the source file."
            )
        }

        if let instrumented = ActivationInstrumenter(importStyle: importStyle).instrument(mutant) {
            let verdict = try await runXcode(
                XcodeAttempt(
                    mutant: mutant, content: instrumented, measured: true, scheme: scheme,
                    configuration: configuration
                ),
                pool: pool
            )
            if !verdict.buildFailed {
                return await record(verdict, mutant: mutant, configuration: configuration)
            }
        }

        let verdict = try await runXcode(
            XcodeAttempt(
                mutant: mutant, content: content, measured: false, scheme: scheme, configuration: configuration
            ),
            pool: pool
        )
        return await record(verdict, mutant: mutant, configuration: configuration)
    }

    private struct XcodeAttempt {
        let mutant: MutantDescriptor
        let content: String
        let measured: Bool
        let scheme: String
        let configuration: RunnerConfiguration
    }

    private struct XcodeRun {
        let attempt: XcodeAttempt
        let slot: SimulatorSlot
        let sandbox: Sandbox
    }

    private func runXcode(_ attempt: XcodeAttempt, pool: SimulatorPool) async throws -> Verdict {
        let configuration = attempt.configuration
        let sandbox = try await sandboxFactory.create(
            projectPath: configuration.projectPath,
            mutatedFilePath: attempt.mutant.filePath,
            mutatedContent: attempt.content
        )
        defer { sandbox.release(keepingFor: configuration.build.reproduction) }

        let slot = try await pool.acquire()
        do {
            let run = XcodeRun(attempt: attempt, slot: slot, sandbox: sandbox)
            var verdict = try await buildAndTestXcode(run)
            if verdict.isUnactivatedKill {
                verdict = try await testXcode(run, start: Date())
            }
            await pool.release(slot)
            return verdict
        } catch {
            await pool.release(slot)
            throw error
        }
    }

    private func buildAndTestXcode(_ run: XcodeRun) async throws -> Verdict {
        let configuration = run.attempt.configuration
        let start = Date()

        let build = try await deps.launcher.launchCapturing(
            ToolRequests.buildForTesting(
                in: run.sandbox,
                scheme: run.attempt.scheme,
                destination: run.slot.destination,
                arguments: configuration.build.xcodeArguments,
                timeout: configuration.build.buildTimeout
            )
        )

        guard build.exitCode == 0 else {
            try rejectTimedOut(build, configuration: configuration)
            let launched = TestLaunchResult(
                exitCode: build.exitCode,
                output: build.output,
                xcresultPath: xcresultPath(in: run.sandbox),
                duration: Date().timeIntervalSince(start)
            )
            var verdict = Verdict(
                raw: try await resolve(launched, configuration: configuration),
                output: build.output, duration: launched.duration, marker: nil
            )
            verdict.buildFailed = true
            return verdict
        }

        return try await testXcode(run, start: start)
    }

    private func testXcode(_ run: XcodeRun, start: Date) async throws -> Verdict {
        let configuration = run.attempt.configuration
        let xcresultPath = xcresultPath(in: run.sandbox)
        var testArguments =
            [
                "test-without-building",
                "-scheme", run.attempt.scheme,
                "-destination", run.slot.destination,
                "-derivedDataPath", ToolRequests.derivedDataPath(in: run.sandbox),
                "-resultBundlePath", xcresultPath,
                "-parallel-testing-enabled", "NO",
            ] + ToolRequests.noTestDiagnostics + configuration.build.xcodeArguments

        if let testTarget = configuration.build.testTarget {
            testArguments += ["-only-testing", testTarget]
        }

        let marker = run.attempt.measured ? ActivationMarker(for: run.attempt.mutant.id, in: run.sandbox) : nil
        let environment = marker.map { [Self.testRunnerPrefix + ActivationMarker.environmentVariable: $0.path] }
        let test = try await deps.launcher.launchCapturing(
            ToolRequests.xcodebuild(
                testArguments, in: run.sandbox, environment: environment ?? [:], timeout: configuration.build.timeout
            )
        )

        let launched = TestLaunchResult(
            exitCode: test.exitCode,
            output: test.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
        return Verdict(
            raw: try await resolve(launched, configuration: configuration),
            output: test.output, duration: launched.duration, marker: marker
        )
    }

    static let testRunnerPrefix = "TEST_RUNNER_"

    private func resolve(
        _ launched: TestLaunchResult,
        configuration: RunnerConfiguration
    ) async throws -> ExecutionStatus {
        try await TestResultResolver(launcher: deps.launcher).resolve(
            launch: launched,
            projectType: configuration.build.projectType,
            timeout: configuration.build.timeout
        ).asExecutionStatus
    }

    private func xcresultPath(in sandbox: Sandbox) -> String {
        sandbox.rootURL.appendingPathComponent("\(UUID().uuidString).xcresult").path
    }
}
