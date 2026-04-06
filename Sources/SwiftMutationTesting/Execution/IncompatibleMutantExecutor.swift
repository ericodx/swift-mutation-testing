import Foundation

struct IncompatibleMutantExecutor: Sendable {
    let deps: ExecutionDeps
    let sandboxFactory: SandboxFactory

    func execute(
        _ mutants: [MutantDescriptor],
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        var pending: [MutantDescriptor] = []

        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant)

            if !configuration.build.noCache, let cachedStatus = await deps.cacheStore.result(for: key) {
                let killerTestFile = await deps.cacheStore.killerTestFile(for: key)
                let total = deps.counter.total
                let index = await deps.counter.increment()
                await deps.reporter.report(
                    .mutantFinished(descriptor: mutant, status: cachedStatus, index: index, total: total))
                results.append(
                    ExecutionResult(
                        descriptor: mutant, status: cachedStatus, testDuration: 0, killerTestFile: killerTestFile
                    ))
                continue
            }

            pending.append(mutant)
        }

        if case .spm = configuration.build.projectType {
            results += try await runSPMShared(
                mutants: pending, configuration: configuration)
        } else if case .xcode(let scheme, _) = configuration.build.projectType {
            for mutant in pending {
                let key = MutantCacheKey.make(for: mutant)
                results.append(
                    try await run(
                        mutant: mutant, key: key, scheme: scheme,
                        configuration: configuration, pool: pool))
            }
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
            let key = MutantCacheKey.make(for: mutant)
            results.append(await storeAndReport(mutant: mutant, key: key, sandbox: nil))
        }

        guard !viable.isEmpty else { return results }

        let sandbox = try await sandboxFactory.createClean(projectPath: configuration.projectPath)

        let initialBuild = try await deps.launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: spmBuildArguments(),
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: configuration.build.timeout
            )
        )

        guard initialBuild.exitCode == 0 else {
            for mutant in viable {
                let key = MutantCacheKey.make(for: mutant)
                results.append(await storeAndReport(mutant: mutant, key: key, sandbox: nil))
            }
            try? sandbox.cleanup()
            return results
        }

        for mutant in viable {
            let key = MutantCacheKey.make(for: mutant)
            let result = try await runInSharedSandbox(
                mutant: mutant,
                key: key,
                configuration: configuration,
                sandbox: sandbox
            )
            results.append(result)
        }

        try? sandbox.cleanup()
        return results
    }

    private func spmBuildArguments() -> [String] {
        ["build", "--build-tests"]
    }

    private func runInSharedSandbox(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> ExecutionResult {
        let projectRoot = URL(fileURLWithPath: configuration.projectPath)
            .resolvingSymlinksInPath().path
        let sandboxRoot = sandbox.rootURL.resolvingSymlinksInPath().path

        let originalCanonical = URL(fileURLWithPath: mutant.filePath).resolvingSymlinksInPath().path
        let content = mutant.mutatedSourceContent!
        let relative = String(originalCanonical.dropFirst(projectRoot.count))
        let sandboxFilePath = sandboxRoot + relative

        try content.write(toFile: sandboxFilePath, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: sandboxFilePath)
            try? FileManager.default.createSymbolicLink(atPath: sandboxFilePath, withDestinationPath: originalCanonical)
        }

        try? FileManager.default.removeItem(
            at: sandbox.rootURL.appendingPathComponent(".build/manifests")
        )

        let build = try await deps.launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: spmBuildArguments(),
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: configuration.build.timeout
            )
        )

        guard build.exitCode == 0 else {
            return await storeAndReport(mutant: mutant, key: key, sandbox: nil)
        }

        return try await runSPMTest(
            mutant: mutant, key: key, configuration: configuration, sandbox: sandbox
        )
    }

    private func runSPMTest(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        configuration: RunnerConfiguration,
        sandbox: Sandbox
    ) async throws -> ExecutionResult {
        var testArgs = ["test", "--skip-build"]
        if let testTarget = configuration.build.testTarget {
            testArgs += ["--filter", testTarget]
        }

        let start = Date()
        let test = try await deps.launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: testArgs,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: configuration.build.timeout
            )
        )
        let duration = Date().timeIntervalSince(start)

        let outcome = SPMResultParser().parse(exitCode: test.exitCode, output: test.output)
        let status = outcome.asExecutionStatus
        let killerTestFile = resolveKillerTestFile(status: status)

        let index = await deps.counter.increment()
        await deps.reporter.report(
            .mutantFinished(descriptor: mutant, status: status, index: index, total: deps.counter.total))
        await deps.cacheStore.store(status: status, for: key, killerTestFile: killerTestFile)

        return ExecutionResult(
            descriptor: mutant, status: status, testDuration: duration, killerTestFile: killerTestFile
        )
    }

    private func run(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        scheme: String,
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
        let launched: TestLaunchResult
        do {
            launched = try await launchXcode(
                scheme: scheme, slot: slot, sandbox: sandbox, configuration: configuration)
        } catch {
            await pool.release(slot)
            try? sandbox.cleanup()
            throw error
        }

        await pool.release(slot)

        let outcome = try await TestResultResolver(launcher: deps.launcher).resolve(
            launch: launched,
            projectType: configuration.build.projectType,
            timeout: configuration.build.timeout
        )

        try? sandbox.cleanup()

        let status = outcome.asExecutionStatus
        let killerTestFile = resolveKillerTestFile(status: status)
        let total = deps.counter.total
        let index = await deps.counter.increment()
        await deps.reporter.report(.mutantFinished(descriptor: mutant, status: status, index: index, total: total))
        await deps.cacheStore.store(status: status, for: key, killerTestFile: killerTestFile)
        return ExecutionResult(
            descriptor: mutant, status: status, testDuration: launched.duration, killerTestFile: killerTestFile
        )
    }

    private func launchXcode(
        scheme: String,
        slot: SimulatorSlot,
        sandbox: Sandbox,
        configuration: RunnerConfiguration
    ) async throws -> TestLaunchResult {
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
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: configuration.build.timeout
            )
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }

    private func resolveKillerTestFile(status: ExecutionStatus) -> String? {
        guard case .killed(let testName) = status else { return nil }
        return deps.killerTestFileResolver.resolve(testName: testName)
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
