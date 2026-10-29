import Foundation

struct IncompatibleMutantExecutor: Sendable {
    let deps: ExecutionDeps
    let sandboxFactory: SandboxFactory
    var importStyle: ImportStyle = .implicit

    static let warmSandboxShare = 4

    func execute(
        _ mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        pool: SimulatorPool,
        reusing sandbox: Sandbox? = nil
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
            results += try await runSPMShared(mutants: pending, configuration: configuration, reusing: sandbox)
        } else if case .xcode(let scheme, _) = configuration.build.projectType {
            results += try await runXcode(
                pending, scheme: scheme, configuration: configuration, pool: pool, reusing: sandbox
            )
        }

        return results
    }

    struct WarmMutant: Sendable {
        let index: Int
        let mutant: MutantDescriptor
        let content: String
    }

    struct WarmOutcome: Sendable {
        let slot: Int
        let build: (exitCode: Int32, output: String)
        let readyAt: Date?
        let results: [(Int, ExecutionResult)]
    }

    private func runSPMShared(
        mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        reusing sandbox: Sandbox?
    ) async throws -> [ExecutionResult] {
        let (unviable, viable) = await separateViable(mutants, configuration: configuration)
        var results = unviable

        if !viable.isEmpty {
            let width = max(1, min(configuration.build.concurrency / Self.warmSandboxShare, viable.count))
            let warm = try await runOnWarmSandboxes(viable, width: width, configuration: configuration) { slot, queue in
                try await warmSPMWorker(slot: slot, queue: queue, reusing: sandbox, configuration: configuration)
            }
            for (index, result) in warm {
                results[index] = result
            }
        }

        return mutants.indices.compactMap { results[$0] }
    }

    private func warmSPMWorker(
        slot: Int, queue: MutantQueue, reusing reused: Sandbox?, configuration: RunnerConfiguration
    ) async throws -> WarmOutcome {
        let reusing = slot == 0 && reused != nil
        let sandbox: Sandbox
        if reusing, let reused {
            sandbox = reused
        } else {
            sandbox = try await sandboxFactory.createClean(projectPath: configuration.projectPath)
        }
        defer {
            if !reusing { sandbox.release(keepingFor: configuration.build.reproduction) }
        }

        let build = try await deps.launcher.launchCapturing(
            ToolRequests.swiftBuildTests(in: sandbox, timeout: configuration.build.buildTimeout)
        )
        guard build.exitCode == 0 else { return WarmOutcome(slot: slot, build: build, readyAt: nil, results: []) }

        let readyAt = Date()
        let results = try await drain(queue) { warm in
            try await runInSharedSandbox(
                mutant: warm.mutant, content: warm.content, configuration: configuration, sandbox: sandbox
            )
        }
        return WarmOutcome(slot: slot, build: build, readyAt: readyAt, results: results)
    }

    func separateViable(
        _ mutants: [MutantDescriptor], configuration: RunnerConfiguration
    ) async -> ([Int: ExecutionResult], [WarmMutant]) {
        var results: [Int: ExecutionResult] = [:]
        var viable: [WarmMutant] = []
        for (index, mutant) in mutants.enumerated() {
            guard let content = mutant.mutatedSourceContent else {
                results[index] = await storeAndReport(
                    mutant: mutant, sandbox: nil, keepLogsPath: configuration.reporting.keepLogsPath,
                    buildOutput: "The mutation could not be applied to the source file."
                )
                continue
            }
            viable.append(WarmMutant(index: index, mutant: mutant, content: content))
        }
        return (results, viable)
    }

    func runOnWarmSandboxes(
        _ viable: [WarmMutant],
        width: Int,
        configuration: RunnerConfiguration,
        worker: @escaping @Sendable (Int, MutantQueue) async throws -> WarmOutcome
    ) async throws -> [(Int, ExecutionResult)] {
        let queue = MutantQueue(viable)
        let start = Date()
        let outcomes = try await withThrowingTaskGroup(of: WarmOutcome.self) { group in
            for slot in 0 ..< width {
                group.addTask { try await worker(slot, queue) }
            }
            var outcomes: [WarmOutcome] = []
            for try await outcome in group { outcomes.append(outcome) }
            return outcomes
        }
        return try await settle(outcomes, queue: queue, start: start, configuration: configuration)
    }

    func drain(
        _ queue: MutantQueue, running run: (WarmMutant) async throws -> ExecutionResult
    ) async throws -> [(Int, ExecutionResult)] {
        var done: [(Int, ExecutionResult)] = []
        while let warm = await queue.next() {
            done.append((warm.index, try await run(warm)))
        }
        return done
    }

    private func settle(
        _ outcomes: [WarmOutcome], queue: MutantQueue, start: Date, configuration: RunnerConfiguration
    ) async throws -> [(Int, ExecutionResult)] {
        let ordered = outcomes.sorted { $0.slot < $1.slot }
        var results = ordered.flatMap(\.results)

        guard let firstReady = ordered.compactMap(\.readyAt).min() else {
            await deps.timings.record(.warmSandboxes, start: start)
            let failed = ordered[0].build
            try rejectTimedOut(failed, configuration: configuration)
            for warm in await queue.drain() {
                results.append(
                    (
                        warm.index,
                        await storeAndReport(
                            mutant: warm.mutant, sandbox: nil, keepLogsPath: configuration.reporting.keepLogsPath,
                            buildOutput: failed.output
                        )
                    )
                )
            }
            return results
        }

        await deps.timings.record(.warmSandboxes, start: start, end: firstReady)
        await deps.timings.record(.incompatible, start: firstReady)
        return results
    }

    private func runInSharedSandbox(
        mutant: MutantDescriptor,
        content: String,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> ExecutionResult {
        let projectRoot = URL(fileURLWithPath: configuration.projectPath)
            .resolvingSymlinksInPath().path
        let sandboxRoot = sandbox.rootURL.resolvingSymlinksInPath().path

        let originalCanonical = URL(fileURLWithPath: mutant.filePath).resolvingSymlinksInPath().path
        guard originalCanonical.hasPrefix(projectRoot + "/") else {
            return await storeAndReport(
                mutant: mutant, sandbox: nil,
                keepLogsPath: configuration.reporting.keepLogsPath,
                buildOutput: Self.outsideProjectMessage
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
            try rejectTimedOut(build, configuration: configuration)
            return await storeAndReport(
                mutant: mutant, sandbox: nil,
                keepLogsPath: configuration.reporting.keepLogsPath,
                buildOutput: build.output
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
        try LintSuppression.wrapping(content).write(toFile: path, atomically: true, encoding: .utf8)
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
            let outcome = SPMResultParser().parse(exitCode: targeted.exitCode, output: targeted.output)
            if outcome.isDetected {
                return Verdict(
                    raw: outcome.asExecutionStatus, output: targeted.output,
                    duration: Date().timeIntervalSince(start), marker: marker
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

    static let outsideProjectMessage = "The mutated file lies outside the project, so no sandbox holds it."

    func storeAndReport(
        mutant: MutantDescriptor,
        sandbox: Sandbox?,
        keepLogsPath: String?,
        buildOutput: String = ""
    ) async -> ExecutionResult {
        try? sandbox?.cleanup()
        return await ResultRecorder(deps: deps, keepLogsPath: keepLogsPath).record(
            mutant, status: .unviable, output: buildOutput
        )
    }

    func rejectTimedOut(_ build: (exitCode: Int32, output: String), configuration: RunnerConfiguration) throws {
        guard build.exitCode == SPMResultParser.timedOutExitCode else { return }
        throw BuildError.timedOut(seconds: configuration.build.buildTimeout, output: build.output)
    }
}
