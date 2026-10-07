import Foundation

struct IncompatibleMutantExecutor: Sendable {
    let deps: ExecutionDeps
    let sandboxFactory: SandboxFactory
    var importStyle: ImportStyle = .implicit

    func execute(
        _ mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        var pending: [MutantDescriptor] = []

        for mutant in mutants {
            if let cached = await ResultRecorder(deps: deps, keepLogsPath: configuration.reporting.keepLogsPath)
                .cached(mutant)
            {
                results.append(cached)
                continue
            }

            pending.append(mutant)
        }

        if case .spm = configuration.build.projectType {
            results += try await runSPMShared(
                mutants: pending, configuration: configuration)
        } else if case .xcode(let scheme, _) = configuration.build.projectType {
            results += try await runXcode(pending, scheme: scheme, configuration: configuration, pool: pool)
        }

        return results
    }

    private func runSPMShared(
        mutants: [MutantDescriptor],
        configuration: RunnerConfiguration
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        let viable = mutants.filter { $0.mutatedSourceContent != nil }

        for mutant in mutants where mutant.mutatedSourceContent == nil {
            results.append(
                await storeAndReport(
                    mutant: mutant, sandbox: nil,
                    keepLogsPath: configuration.reporting.keepLogsPath,
                    buildOutput: "The mutation could not be applied to the source file."
                )
            )
        }

        guard !viable.isEmpty else { return results }

        let share = TestExecutionStage.retryWorkerShare
        let workerCount = max(1, min(configuration.build.concurrency / share, viable.count))
        let workers = try await warmSandboxes(count: workerCount, configuration: configuration)
        defer {
            for worker in workers { worker.sandbox.release(keepingFor: configuration.build.reproduction) }
        }

        let ready = workers.filter { $0.build.exitCode == 0 }

        guard !ready.isEmpty else {
            let failed = workers[0].build
            for mutant in viable {
                results.append(
                    await storeAndReport(
                        mutant: mutant, sandbox: nil,
                        keepLogsPath: configuration.reporting.keepLogsPath,
                        buildOutput: failed.output,
                        status: buildStatus(exitCode: failed.exitCode)
                    )
                )
            }
            return results
        }

        results += try await runRoundRobin(viable, over: ready, configuration: configuration)
        return results
    }

    private func runRoundRobin(
        _ mutants: [MutantDescriptor],
        over ready: [WarmSandbox],
        configuration: RunnerConfiguration
    ) async throws -> [ExecutionResult] {
        let numbered = Array(mutants.enumerated())
        let finished = try await withThrowingTaskGroup(of: [(Int, ExecutionResult)].self) { group in
            for (slot, worker) in ready.enumerated() {
                let mine = numbered.filter { $0.offset % ready.count == slot }
                group.addTask {
                    var done: [(Int, ExecutionResult)] = []
                    for (offset, mutant) in mine {
                        let result = try await runInSharedSandbox(
                            mutant: mutant, configuration: configuration, sandbox: worker.sandbox
                        )
                        done.append((offset, result))
                    }
                    return done
                }
            }

            var all: [(Int, ExecutionResult)] = []
            for try await part in group { all += part }
            return all
        }

        return finished.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private struct WarmSandbox: Sendable {
        let sandbox: Sandbox
        let build: (exitCode: Int32, output: String)
    }

    private func warmSandboxes(count: Int, configuration: RunnerConfiguration) async throws -> [WarmSandbox] {
        try await withThrowingTaskGroup(of: (Int, WarmSandbox).self) { group in
            for slot in 0 ..< count {
                group.addTask {
                    let sandbox = try await sandboxFactory.createClean(projectPath: configuration.projectPath)
                    let build = try await deps.launcher.launchCapturing(
                        ToolRequests.swiftBuildTests(in: sandbox, timeout: configuration.build.buildTimeout)
                    )
                    return (slot, WarmSandbox(sandbox: sandbox, build: build))
                }
            }

            var warmed: [(Int, WarmSandbox)] = []
            for try await entry in group { warmed.append(entry) }
            return warmed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func runInSharedSandbox(
        mutant: MutantDescriptor,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> ExecutionResult {
        let projectRoot = URL(fileURLWithPath: configuration.projectPath)
            .resolvingSymlinksInPath().path
        let sandboxRoot = sandbox.rootURL.resolvingSymlinksInPath().path

        let originalCanonical = URL(fileURLWithPath: mutant.filePath).resolvingSymlinksInPath().path
        guard let content = mutant.mutatedSourceContent else {
            return await storeAndReport(
                mutant: mutant, sandbox: nil,
                keepLogsPath: configuration.reporting.keepLogsPath,
                buildOutput: "The mutation could not be applied to the source file."
            )
        }
        let relative = String(originalCanonical.dropFirst(projectRoot.count))
        let sandboxFilePath = sandboxRoot + relative

        do {
            let result = try await buildAndTest(
                mutant: mutant, content: content, at: sandboxFilePath, configuration: configuration, sandbox: sandbox
            )
            try SandboxLink.restore(at: sandboxFilePath, to: originalCanonical)
            return result
        } catch {
            try? SandboxLink.restore(at: sandboxFilePath, to: originalCanonical)
            throw error
        }
    }

    private func buildAndTest(
        mutant: MutantDescriptor,
        content: String,
        at sandboxFilePath: String,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> ExecutionResult {
        let instrumented = ActivationInstrumenter(importStyle: importStyle).instrument(mutant)
        var measured = instrumented != nil
        var build = try await buildSPM(
            writing: instrumented ?? content, to: sandboxFilePath, configuration: configuration, sandbox: sandbox
        )

        if measured, build.exitCode != 0, build.exitCode != SPMResultParser.timedOutExitCode {
            measured = false
            build = try await buildSPM(
                writing: content, to: sandboxFilePath, configuration: configuration, sandbox: sandbox
            )
        }

        guard build.exitCode == 0 else {
            return await storeAndReport(
                mutant: mutant, sandbox: nil,
                keepLogsPath: configuration.reporting.keepLogsPath,
                buildOutput: build.output,
                status: buildStatus(exitCode: build.exitCode)
            )
        }

        var verdict = try await testSPM(
            mutant: mutant, configuration: configuration, sandbox: sandbox, measured: measured
        )
        if verdict.isUnactivatedKill {
            verdict = try await testSPM(
                mutant: mutant, configuration: configuration, sandbox: sandbox, measured: measured
            )
        }
        return await record(verdict, mutant: mutant, configuration: configuration)
    }

    private func buildSPM(
        writing content: String,
        to path: String,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> (exitCode: Int32, output: String) {
        try? FileManager.default.removeItem(atPath: path)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: sandbox.rootURL.appendingPathComponent(".build/manifests"))

        return try await deps.launcher.launchCapturing(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: configuration.build.buildTimeout)
        )
    }

    struct Verdict {
        let status: ExecutionStatus
        let output: String
        let duration: Double
        let activated: Bool?
        var buildFailed = false

        var isUnactivatedKill: Bool {
            activated == false && status.isKill
        }

        init(raw: ExecutionStatus, output: String, duration: Double, marker: ActivationMarker?) {
            let activated = marker?.wasWritten()
            self.status = activated.map { TestExecutionStage.classify(raw, activated: $0) } ?? raw
            self.output = output
            self.duration = duration
            self.activated = activated
        }
    }

    private func testSPM(
        mutant: MutantDescriptor,
        configuration: RunnerConfiguration,
        sandbox: Sandbox,
        measured: Bool
    ) async throws -> Verdict {
        let marker = measured ? ActivationMarker(for: mutant.id, in: sandbox) : nil
        let start = Date()

        if !configuration.build.reproducing,
            let suite = TargetedSuites.suite(for: mutant.filePath, among: deps.targetedSuites)
        {
            let targeted = try await swiftTest(
                filter: suite.name, marker: marker, configuration: configuration, sandbox: sandbox)
            let status = SPMResultParser().parse(exitCode: targeted.exitCode, output: targeted.output)
                .asExecutionStatus
            if status.isKill {
                return Verdict(
                    raw: status, output: targeted.output, duration: Date().timeIntervalSince(start), marker: marker
                )
            }
        }

        let test = try await swiftTest(
            filter: configuration.build.testTarget, marker: marker, configuration: configuration, sandbox: sandbox)

        return Verdict(
            raw: SPMResultParser().parse(exitCode: test.exitCode, output: test.output).asExecutionStatus,
            output: test.output,
            duration: Date().timeIntervalSince(start),
            marker: marker
        )
    }

    private func swiftTest(
        filter: String?,
        marker: ActivationMarker?,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> (exitCode: Int32, output: String) {
        let request = ToolRequests.swiftTest(
            in: sandbox,
            filter: filter,
            environment: marker.map { [ActivationMarker.environmentVariable: $0.path] } ?? [:],
            timeout: configuration.build.timeout
        )
        return try await deps.launcher.launchCapturing(
            configuration.build.reproducing ? request : request.stopping(at: .firstTestFailure)
        )
    }

    func record(
        _ verdict: Verdict,
        mutant: MutantDescriptor,
        configuration: RunnerConfiguration
    ) async -> ExecutionResult {
        await ResultRecorder(deps: deps, keepLogsPath: configuration.reporting.keepLogsPath).record(
            mutant, status: verdict.status, duration: verdict.duration, output: verdict.output,
            activated: verdict.activated
        )
    }

    func storeAndReport(
        mutant: MutantDescriptor,
        sandbox: Sandbox?,
        keepLogsPath: String?,
        buildOutput: String = "",
        status: ExecutionStatus = .unviable
    ) async -> ExecutionResult {
        try? sandbox?.cleanup()
        return await ResultRecorder(deps: deps, keepLogsPath: keepLogsPath).record(
            mutant, status: status, output: buildOutput
        )
    }

    func buildStatus(exitCode: Int32) -> ExecutionStatus {
        exitCode == SPMResultParser.timedOutExitCode ? .timeout : .unviable
    }
}
