import Foundation

extension IncompatibleMutantExecutor {
    func runXcode(
        _ mutants: [MutantDescriptor],
        scheme: String,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        guard !configuration.build.reproducing else {
            return try await runXcodeCold(mutants, scheme: scheme, configuration: configuration, pool: pool)
        }

        var results: [Int: ExecutionResult] = [:]
        var viable: [(Int, MutantDescriptor)] = []
        for (index, mutant) in mutants.enumerated() {
            guard mutant.mutatedSourceContent != nil else {
                results[index] = await storeAndReport(
                    mutant: mutant, sandbox: nil, keepLogsPath: configuration.reporting.keepLogsPath,
                    buildOutput: "The mutation could not be applied to the source file."
                )
                continue
            }
            viable.append((index, mutant))
        }

        if !viable.isEmpty {
            let width = Self.xcodeWidth(
                concurrency: configuration.build.concurrency, poolSize: pool.size, mutantCount: viable.count
            )
            let workers = try await warmXcodeWorkers(
                count: width, scheme: scheme, configuration: configuration, pool: pool
            )
            do {
                for (index, result) in try await runXcodeWarm(viable, on: workers, configuration: configuration) {
                    results[index] = result
                }
            } catch {
                await release(workers, to: pool)
                throw error
            }
            await release(workers, to: pool)
        }

        return mutants.indices.compactMap { results[$0] }
    }

    struct XcodeWorker: Sendable {
        let sandbox: Sandbox
        let slot: SimulatorSlot
        let scheme: String
        let build: (exitCode: Int32, output: String)
    }

    private func warmXcodeWorkers(
        count: Int, scheme: String, configuration: RunnerConfiguration, pool: SimulatorPool
    ) async throws -> [XcodeWorker] {
        try await withThrowingTaskGroup(of: (Int, XcodeWorker).self) { group in
            for index in 0 ..< count {
                group.addTask {
                    let slot = try await pool.acquire()
                    do {
                        let sandbox = try await sandboxFactory.createClean(
                            projectPath: configuration.projectPath, disablingSwiftLint: true
                        )
                        let build = try await deps.launcher.launchCapturing(
                            ToolRequests.buildForTesting(
                                in: sandbox, scheme: scheme, destination: slot.destination,
                                container: configuration.build.xcodeContainer,
                                timeout: configuration.build.buildTimeout
                            )
                        )
                        return (index, XcodeWorker(sandbox: sandbox, slot: slot, scheme: scheme, build: build))
                    } catch {
                        await pool.release(slot)
                        throw error
                    }
                }
            }

            var warmed: [(Int, XcodeWorker)] = []
            do {
                for try await worker in group { warmed.append(worker) }
            } catch {
                await release(warmed.map(\.1), to: pool)
                throw error
            }
            return warmed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func release(_ workers: [XcodeWorker], to pool: SimulatorPool) async {
        for worker in workers {
            worker.sandbox.release(keepingFor: nil)
            await pool.release(worker.slot)
        }
    }

    private func runXcodeWarm(
        _ mutants: [(Int, MutantDescriptor)],
        on workers: [XcodeWorker],
        configuration: RunnerConfiguration
    ) async throws -> [(Int, ExecutionResult)] {
        let ready = workers.filter { $0.build.exitCode == 0 }

        guard !ready.isEmpty else {
            let failed = workers[0].build
            var results: [(Int, ExecutionResult)] = []
            for (index, mutant) in mutants {
                results.append(
                    (
                        index,
                        await storeAndReport(
                            mutant: mutant, sandbox: nil, keepLogsPath: configuration.reporting.keepLogsPath,
                            buildOutput: failed.output, status: buildStatus(exitCode: failed.exitCode)
                        )
                    )
                )
            }
            return results
        }

        let numbered = Array(mutants.enumerated())
        return try await withThrowingTaskGroup(of: [(Int, ExecutionResult)].self) { group in
            for (slot, worker) in ready.enumerated() {
                let mine = numbered.filter { $0.offset % ready.count == slot }.map(\.element)
                group.addTask {
                    var done: [(Int, ExecutionResult)] = []
                    for (index, mutant) in mine {
                        done.append((index, try await runWarm(mutant, on: worker, configuration: configuration)))
                    }
                    return done
                }
            }

            var all: [(Int, ExecutionResult)] = []
            for try await part in group { all += part }
            return all
        }
    }

    private func runWarm(
        _ mutant: MutantDescriptor, on worker: XcodeWorker, configuration: RunnerConfiguration
    ) async throws -> ExecutionResult {
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
                mutant, at: sandboxPath, on: worker, configuration: configuration
            )
            try SandboxLink.restore(at: sandboxPath, to: originalPath)
            removeResultBundles(in: worker.sandbox)
            return result
        } catch {
            try? SandboxLink.restore(at: sandboxPath, to: originalPath)
            removeResultBundles(in: worker.sandbox)
            throw error
        }
    }

    private func buildAndTestWarm(
        _ mutant: MutantDescriptor, at sandboxPath: String, on worker: XcodeWorker,
        configuration: RunnerConfiguration
    ) async throws -> ExecutionResult {
        let content = mutant.mutatedSourceContent ?? ""

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
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func removeResultBundles(in sandbox: Sandbox) {
        let root = sandbox.rootURL
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasSuffix(".xcresult") {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }

    static func xcodeWidth(concurrency: Int, poolSize: Int, mutantCount: Int) -> Int {
        max(1, min(concurrency / TestExecutionStage.retryWorkerShare, poolSize, mutantCount))
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
                container: configuration.build.xcodeContainer,
                timeout: configuration.build.buildTimeout
            )
        )

        guard build.exitCode == 0 else {
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
            ] + (configuration.build.xcodeContainer?.arguments ?? [])

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
