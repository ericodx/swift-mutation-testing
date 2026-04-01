import Foundation

struct IncompatibleMutantExecutor: Sendable {
    let deps: ExecutionDeps
    let sandboxFactory: SandboxFactory

    func execute(
        _ mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)

            if !configuration.build.noCache, let cachedStatus = await deps.cacheStore.result(for: key) {
                let total = deps.counter.total
                let index = await deps.counter.increment()
                await deps.reporter.report(
                    .mutantFinished(descriptor: mutant, status: cachedStatus, index: index, total: total))
                results.append(ExecutionResult(descriptor: mutant, status: cachedStatus, testDuration: 0))
                continue
            }

            let result = try await run(mutant: mutant, key: key, configuration: configuration, pool: pool)
            results.append(result)
        }

        return results
    }

    private func run(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> ExecutionResult {
        guard let content = mutant.mutatedSourceContent else {
            return await storeAndReport(mutant: mutant, key: key, sandbox: nil)
        }

        let sandbox = try await sandboxFactory.create(
            projectPath: configuration.projectPath,
            mutatedFilePath: mutant.filePath,
            mutatedContent: content
        )

        let slot = try await pool.acquire()
        let launched: IncompatibleTestLaunchResult
        do {
            launched = try await launch(slot: slot, sandbox: sandbox, configuration: configuration)
        } catch {
            await pool.release(slot)
            try? sandbox.cleanup()
            throw error
        }

        let duration = launched.duration
        await pool.release(slot)

        let outcome: TestRunOutcome
        switch configuration.build.projectType {
        case .xcode:
            outcome = try await ResultParser(launcher: deps.launcher).parse(
                exitCode: launched.exitCode,
                output: launched.output,
                xcresultPath: launched.xcresultPath,
                timeout: configuration.build.timeout
            )

        case .spm:
            outcome = SPMResultParser().parse(exitCode: launched.exitCode, output: launched.output)
        }

        try? sandbox.cleanup()

        let status = outcome.asExecutionStatus
        let total = deps.counter.total
        let index = await deps.counter.increment()
        await deps.reporter.report(.mutantFinished(descriptor: mutant, status: status, index: index, total: total))
        await deps.cacheStore.store(status: status, for: key)
        return ExecutionResult(descriptor: mutant, status: status, testDuration: duration)
    }

    private func launch(
        slot: SimulatorSlot,
        sandbox: Sandbox,
        configuration: RunnerConfiguration
    ) async throws -> IncompatibleTestLaunchResult {
        switch configuration.build.projectType {
        case .xcode(let scheme, _):
            return try await launchXcode(
                scheme: scheme, slot: slot, sandbox: sandbox, configuration: configuration)
        case .spm:
            return try await launchSPM(sandbox: sandbox, configuration: configuration)
        }
    }

    private func launchXcode(
        scheme: String,
        slot: SimulatorSlot,
        sandbox: Sandbox,
        configuration: RunnerConfiguration
    ) async throws -> IncompatibleTestLaunchResult {
        let derivedDataPath = sandbox.rootURL.appendingPathComponent(".derived-data").path
        let xcresultPath = sandbox.rootURL
            .appendingPathComponent("\(UUID().uuidString).xcresult").path

        var arguments = [
            "test",
            "-scheme", scheme,
            "-destination", slot.destination,
            "-derivedDataPath", derivedDataPath,
            "-resultBundlePath", xcresultPath,
            "-parallel-testing-enabled", "NO",
        ]

        if let testTarget = configuration.build.testTarget {
            arguments += ["-only-testing", testTarget]
        }

        let start = Date()
        let captured = try await deps.launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: sandbox.rootURL,
            timeout: configuration.build.timeout
        )

        return IncompatibleTestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }

    private func launchSPM(
        sandbox: Sandbox,
        configuration: RunnerConfiguration
    ) async throws -> IncompatibleTestLaunchResult {
        var arguments = ["test"]

        if let testTarget = configuration.build.testTarget {
            arguments += ["--filter", testTarget]
        }

        let start = Date()
        let captured = try await deps.launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: sandbox.rootURL,
            timeout: configuration.build.timeout
        )

        return IncompatibleTestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: "",
            duration: Date().timeIntervalSince(start)
        )
    }

    private func storeAndReport(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        sandbox: Sandbox?
    ) async -> ExecutionResult {
        try? sandbox?.cleanup()
        await deps.cacheStore.store(status: .unviable, for: key)
        let total = deps.counter.total
        let index = await deps.counter.increment()
        await deps.reporter.report(.mutantFinished(descriptor: mutant, status: .unviable, index: index, total: total))
        return ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0)
    }
}
