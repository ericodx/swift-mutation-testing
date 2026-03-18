import Foundation

struct MutantExecutor: Sendable {

    init(configuration: RunnerConfiguration) {
        self.configuration = configuration
    }

    private let configuration: RunnerConfiguration

    func execute(_ input: RunnerInput) async throws -> [ExecutionResult] {
        let launcher = ProcessLauncher()
        let reporter: any ProgressReporter =
            configuration.quiet
            ? SilentProgressReporter()
            : ConsoleProgressReporter()

        let cachePath = URL(fileURLWithPath: configuration.projectPath)
            .appendingPathComponent(".xmr-cache/results.json").path
        let cacheStore = CacheStore(storePath: cachePath)
        try await cacheStore.load()

        let testFilesHash = TestFilesHasher().hash(projectPath: input.projectPath)

        if let cached = await allCached(mutants: input.mutants, cacheStore: cacheStore, testFilesHash: testFilesHash) {
            return cached
        }

        let schematizable = input.mutants.filter { $0.isSchematizable }
        let incompatible = input.mutants.filter { !$0.isSchematizable }
        let counter = MutationCounter(total: schematizable.count + incompatible.count)
        let deps = ExecutionDeps(launcher: launcher, cacheStore: cacheStore, reporter: reporter, counter: counter)

        let sandbox = try await SandboxFactory().create(
            projectPath: input.projectPath,
            schematizedFiles: input.schematizedFiles,
            supportFileContent: input.supportFileContent
        )

        let artifact = try await buildArtifact(sandbox: sandbox, deps: deps)
        let pool = try await makePool(launcher: launcher)
        try await pool.setUp()
        await reporter.report(.simulatorPoolReady(size: pool.size))

        var results: [ExecutionResult]
        if let artifact {
            let context = TestExecutionContext(
                artifact: artifact, sandbox: sandbox, pool: pool,
                configuration: configuration, testFilesHash: testFilesHash
            )
            results = try await runNormal(deps: deps, context: context, schematizable: schematizable)
        } else {
            results = try await runFallback(deps: deps, input: input, pool: pool, testFilesHash: testFilesHash)
        }

        results += try await runIncompatible(
            deps: deps, mutants: incompatible, pool: pool, testFilesHash: testFilesHash
        )

        await pool.tearDown()
        try? sandbox.cleanup()
        try await cacheStore.persist()

        return results
    }

    private func allCached(
        mutants: [MutantDescriptor],
        cacheStore: CacheStore,
        testFilesHash: String
    ) async -> [ExecutionResult]? {
        guard !configuration.noCache, !mutants.isEmpty else { return nil }

        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)
            guard let status = await cacheStore.result(for: key) else { return nil }
            results.append(ExecutionResult(descriptor: mutant, status: status, testDuration: 0))
        }

        return results
    }

    private func buildArtifact(sandbox: Sandbox, deps: ExecutionDeps) async throws -> BuildArtifact? {
        await deps.reporter.report(.buildStarted)
        let start = Date()

        do {
            let artifact = try await BuildStage(launcher: deps.launcher).build(
                sandbox: sandbox,
                scheme: configuration.scheme,
                destination: configuration.destination,
                timeout: configuration.timeout
            )
            await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
            return artifact
        } catch BuildError.compilationFailed {
            return nil
        }
    }

    private func runNormal(
        deps: ExecutionDeps,
        context: TestExecutionContext,
        schematizable: [MutantDescriptor]
    ) async throws -> [ExecutionResult] {
        try await TestExecutionStage(
            launcher: deps.launcher, cacheStore: deps.cacheStore,
            reporter: deps.reporter, counter: deps.counter
        ).execute(mutants: schematizable, in: context)
    }

    private func runFallback(
        deps: ExecutionDeps,
        input: RunnerInput,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        try await PerFileBuildFallback(
            launcher: deps.launcher, sandboxFactory: SandboxFactory(),
            cacheStore: deps.cacheStore, reporter: deps.reporter, counter: deps.counter
        ).execute(input: input, configuration: configuration, pool: pool, testFilesHash: testFilesHash)
    }

    private func runIncompatible(
        deps: ExecutionDeps,
        mutants: [MutantDescriptor],
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        try await IncompatibleMutantExecutor(
            launcher: deps.launcher, sandboxFactory: SandboxFactory(),
            cacheStore: deps.cacheStore, reporter: deps.reporter, counter: deps.counter
        ).execute(mutants, configuration: configuration, pool: pool, testFilesHash: testFilesHash)
    }

    private func makePool(launcher: any ProcessLaunching) async throws -> SimulatorPool {
        guard SimulatorManager.requiresSimulatorPool(for: configuration.destination) else {
            return SimulatorPool(
                baseUDID: nil, size: 1,
                destination: configuration.destination, launcher: launcher
            )
        }

        let baseUDID = try await SimulatorManager(launcher: launcher)
            .resolveBaseUDID(for: configuration.destination)

        return SimulatorPool(
            baseUDID: baseUDID, size: configuration.concurrency,
            destination: configuration.destination, launcher: launcher
        )
    }
}

private struct ExecutionDeps: Sendable {
    let launcher: any ProcessLaunching
    let cacheStore: CacheStore
    let reporter: any ProgressReporter
    let counter: MutationCounter
}
