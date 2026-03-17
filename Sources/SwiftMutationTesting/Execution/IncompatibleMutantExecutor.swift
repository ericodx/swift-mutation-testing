import Foundation

private struct IncompatibleTestLaunchResult {
    let exitCode: Int32
    let output: String
    let xcresultPath: String
    let duration: Double
}

struct IncompatibleMutantExecutor: Sendable {
    let launcher: any ProcessLaunching
    let sandboxFactory: SandboxFactory
    let cacheStore: CacheStore
    let reporter: any ProgressReporter

    func execute(
        _ mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)

            if !configuration.noCache, let cachedStatus = await cacheStore.result(for: key) {
                let hit = ExecutionResult(descriptor: mutant, status: cachedStatus, testDuration: 0)
                await reporter.report(.mutantTested(result: hit))
                results.append(hit)
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

        let artifact: BuildArtifact
        do {
            artifact = try await BuildStage(launcher: launcher).build(
                sandbox: sandbox,
                scheme: configuration.scheme,
                destination: configuration.destination,
                timeout: configuration.timeout
            )
        } catch {
            return await storeAndReport(mutant: mutant, key: key, sandbox: sandbox)
        }

        let slot = try await pool.acquire()
        let launched: IncompatibleTestLaunchResult
        do {
            launched = try await launch(artifact: artifact, slot: slot, sandbox: sandbox, configuration: configuration)
        } catch {
            await pool.release(slot)
            try? sandbox.cleanup()
            throw error
        }

        let duration = launched.duration
        await pool.release(slot)

        let outcome = try await ResultParser(launcher: launcher).parse(
            exitCode: launched.exitCode,
            output: launched.output,
            xcresultPath: launched.xcresultPath,
            timeout: configuration.timeout
        )

        try? sandbox.cleanup()

        let status = outcome.asExecutionStatus
        await cacheStore.store(status: status, for: key)
        let result = ExecutionResult(descriptor: mutant, status: status, testDuration: duration)
        await reporter.report(.mutantTested(result: result))
        return result
    }

    private func launch(
        artifact: BuildArtifact,
        slot: SimulatorSlot,
        sandbox: Sandbox,
        configuration: RunnerConfiguration
    ) async throws -> IncompatibleTestLaunchResult {
        let xcresultPath = sandbox.rootURL
            .appendingPathComponent("\(UUID().uuidString).xcresult").path

        var arguments = [
            "test-without-building",
            "-xctestrun", artifact.xctestrunURL.path,
            "-destination", slot.destination,
            "-resultBundlePath", xcresultPath,
            "-derivedDataPath", artifact.derivedDataPath,
        ]

        if let testTarget = configuration.testTarget {
            arguments += ["-only-testing", testTarget]
        }

        let start = Date()
        let captured = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: arguments,
            environment: nil,
            workingDirectoryURL: sandbox.rootURL,
            timeout: configuration.timeout
        )

        return IncompatibleTestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }

    private func storeAndReport(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        sandbox: Sandbox?
    ) async -> ExecutionResult {
        try? sandbox?.cleanup()
        await cacheStore.store(status: .unviable, for: key)
        let result = ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0)
        await reporter.report(.mutantTested(result: result))
        return result
    }
}
