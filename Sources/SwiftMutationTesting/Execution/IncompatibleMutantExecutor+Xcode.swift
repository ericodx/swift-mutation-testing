import Foundation

extension IncompatibleMutantExecutor {
    static func xcodeWidth(concurrency: Int, poolSize: Int, mutantCount: Int) -> Int {
        max(1, min(concurrency / TestExecutionStage.retryWorkerShare, poolSize, mutantCount))
    }

    func runXcode(
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
