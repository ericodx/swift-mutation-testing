import Foundation

struct MutantExecutor: Sendable {

    init(configuration: RunnerConfiguration, launcher: any ProcessLaunching = ProcessLauncher()) {
        self.configuration = configuration
        self.launcher = launcher
    }

    private let configuration: RunnerConfiguration
    private let launcher: any ProcessLaunching

    func execute(_ input: RunnerInput) async throws -> [ExecutionResult] {
        let reporter: any ProgressReporter =
            configuration.reporting.quiet
            ? SilentProgressReporter()
            : ConsoleProgressReporter()

        let cachePath = URL(fileURLWithPath: configuration.projectPath)
            .appendingPathComponent("\(CacheStore.directoryName)/results.json").path
        let cacheStore = CacheStore(storePath: cachePath)
        try await cacheStore.load()

        let testFilesHash = TestFilesHasher().hash(projectPath: input.projectPath)

        if let cached = await allCached(mutants: input.mutants, cacheStore: cacheStore, testFilesHash: testFilesHash) {
            await reporter.report(.loadedFromCache(mutantCount: cached.count))
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
        guard !configuration.build.noCache, !mutants.isEmpty else { return nil }

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
        let stage = BuildStage(launcher: deps.launcher)

        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            do {
                let artifact = try await stage.build(
                    sandbox: sandbox,
                    scheme: scheme,
                    destination: destination,
                    timeout: configuration.build.timeout
                )
                await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
                return artifact
            } catch BuildError.compilationFailed {
                return nil
            }

        case .spm:
            let artifact = try await stage.buildSPM(
                sandbox: sandbox,
                testTarget: configuration.build.testTarget,
                timeout: configuration.build.timeout
            )
            await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
            return artifact
        }
    }

    private func runNormal(
        deps: ExecutionDeps,
        context: TestExecutionContext,
        schematizable: [MutantDescriptor]
    ) async throws -> [ExecutionResult] {
        try await TestExecutionStage(deps: deps).execute(mutants: schematizable, in: context)
    }

    private func runFallback(
        deps: ExecutionDeps,
        input: RunnerInput,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        try await FallbackExecutor(deps: deps, configuration: configuration)
            .execute(input: input, pool: pool, testFilesHash: testFilesHash)
    }

    private func runIncompatible(
        deps: ExecutionDeps,
        mutants: [MutantDescriptor],
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        try await IncompatibleMutantExecutor(deps: deps, sandboxFactory: SandboxFactory())
            .execute(mutants, configuration: configuration, pool: pool, testFilesHash: testFilesHash)
    }

    private func makePool(launcher: any ProcessLaunching) async throws -> SimulatorPool {
        let destination: String
        if case .xcode(_, let dest) = configuration.build.projectType {
            destination = dest
        } else {
            destination = "platform=macOS"
        }

        guard SimulatorManager.requiresSimulatorPool(for: destination) else {
            return SimulatorPool(
                baseUDID: nil, size: configuration.build.concurrency,
                destination: destination, launcher: launcher
            )
        }

        let baseUDID = try await SimulatorManager(launcher: launcher)
            .resolveBaseUDID(for: destination)

        return SimulatorPool(
            baseUDID: baseUDID, size: configuration.build.concurrency,
            destination: destination, launcher: launcher
        )
    }
}
