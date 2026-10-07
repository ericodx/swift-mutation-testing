import Foundation

struct MutantExecutor: Sendable {

    struct Environment: Sendable {
        var sandboxFactory = SandboxFactory()
        var verifier = ApplicationVerifier()
        var testFilesHasher = TestFilesHasher()
        var reporter: (any ProgressReporter)?
    }

    init(
        configuration: RunnerConfiguration,
        launcher: any ProcessLaunching,
        planJournal: PlanJournal? = nil,
        environment: Environment = Environment()
    ) {
        self.configuration = configuration
        self.launcher = launcher
        self.planJournal = planJournal
        self.environment = environment
    }

    private let configuration: RunnerConfiguration
    private let launcher: any ProcessLaunching
    private let planJournal: PlanJournal?
    private let environment: Environment

    private struct MutantRunContext {
        let deps: ExecutionDeps
        let input: RunnerInput
        let sandbox: Sandbox
        let pool: SimulatorPool
        let artifact: BuildArtifact?
        let schemaBuildExcluded: [MutantDescriptor]
    }

    func execute(_ input: RunnerInput) async throws -> [ExecutionResult] {
        let reporter: any ProgressReporter =
            environment.reporter
            ?? (configuration.reporting.quiet ? SilentProgressReporter() : ConsoleProgressReporter())

        let (cacheStore, metadata, hasher) = try await prepareCacheStore(input: input)
        try await cacheStore.persistMetadata(metadata)

        if let cached = await allCached(mutants: input.mutants, cacheStore: cacheStore) {
            await reporter.report(.loadedFromCache(mutantCount: cached.count))
            try await cacheStore.persist()
            try await cacheStore.persistMetadata(metadata)
            return cached
        }

        let deps = makeExecutionDeps(
            input: input, hasher: hasher, cacheStore: cacheStore, reporter: reporter
        )

        let sandbox = try await environment.sandboxFactory.create(
            projectPath: input.projectPath,
            schematizedFiles: input.schematizedFiles
        )
        SandboxCleaner.register(sandbox)
        defer {
            sandbox.release(keepingFor: configuration.build.reproduction)
            SandboxCleaner.deregister()
        }

        let results = try await run(input, in: sandbox, deps: deps, reporter: reporter)
        try await cacheStore.persist()
        try await cacheStore.persistMetadata(metadata)

        return results
    }

    private func run(
        _ input: RunnerInput,
        in sandbox: Sandbox,
        deps: ExecutionDeps,
        reporter: any ProgressReporter
    ) async throws -> [ExecutionResult] {
        try environment.verifier.verify(
            schematizedFiles: input.schematizedFiles, mutants: input.mutants,
            sandbox: sandbox, projectPath: input.projectPath
        )

        let (artifact, schemaBuildExcluded) = try await buildArtifact(sandbox: sandbox, input: input, deps: deps)
        let pool = try await SimulatorPool.make(for: configuration, launcher: launcher)
        try await pool.setUp()
        await reporter.report(.workersReady(count: pool.size, usesSimulators: pool.usesSimulators))

        let results: [ExecutionResult]
        do {
            results = try await runAllMutants(
                MutantRunContext(
                    deps: deps,
                    input: input,
                    sandbox: sandbox,
                    pool: pool,
                    artifact: artifact,
                    schemaBuildExcluded: schemaBuildExcluded
                )
            )
            try Self.requireObservedActivation(in: results)
        } catch {
            await pool.tearDown()
            throw error
        }

        await pool.tearDown()
        return results
    }

    private func prepareCacheStore(
        input: RunnerInput
    ) async throws -> (CacheStore, CacheStore.CacheMetadata, TestFilesHasher) {
        let cachePath = URL(fileURLWithPath: configuration.projectPath)
            .appendingPathComponent("\(CacheStore.directoryName)/results.json").path
        let cacheStore = CacheStore(
            storePath: cachePath, noCache: configuration.build.noCache, planJournal: planJournal
        )
        try await cacheStore.load()

        let selection = CacheTestSelection(configuration.build)
        if try await cacheStore.discard(unlessMadeWith: selection) {
            StandardError.write(
                "Note: the cache was made against other tests (another target, testing library, scheme or "
                    + "destination); every mutant will be tested again."
            )
        }

        let hasher = environment.testFilesHasher
        let currentTestHashes = hasher.hashPerFile(projectPath: input.projectPath)
        let diff = try await cacheStore.changedTestFiles(current: currentTestHashes)
        await cacheStore.invalidate(diff: diff)

        let metadata = CacheStore.CacheMetadata(testFileHashes: currentTestHashes, testSelection: selection)
        return (cacheStore, metadata, hasher)
    }

    private func makeExecutionDeps(
        input: RunnerInput,
        hasher: TestFilesHasher,
        cacheStore: CacheStore,
        reporter: any ProgressReporter
    ) -> ExecutionDeps {
        let mutantCount = input.mutants.count
        let counter = MutationCounter(total: mutantCount)
        let resolver = KillerTestFileResolver(
            testFilePaths: hasher.testFilePaths(projectPath: input.projectPath),
            projectPath: input.projectPath
        )
        return ExecutionDeps(
            launcher: launcher, cacheStore: cacheStore, reporter: reporter,
            counter: counter, killerTestFileResolver: resolver
        )
    }

    private func runAllMutants(
        _ context: MutantRunContext
    ) async throws -> [ExecutionResult] {
        let deps = context.deps
        let input = context.input
        let sandbox = context.sandbox
        let pool = context.pool
        let artifact = context.artifact
        let schemaBuildExcluded = context.schemaBuildExcluded
        let schematizable = input.mutants.filter { $0.isSchematizable }
        let incompatible = input.mutants.filter { !$0.isSchematizable }

        var results: [ExecutionResult] = []

        var reroutedToIncompatible: [MutantDescriptor] = []
        var sourceCache: [String: String] = [:]
        let rewriter = MutationRewriter()

        for mutant in schemaBuildExcluded {
            if let rerouted = rewriteForIncompatible(mutant, rewriter: rewriter, sourceCache: &sourceCache) {
                reroutedToIncompatible.append(rerouted)
            } else {
                let recorder = ResultRecorder(deps: deps, keepLogsPath: configuration.reporting.keepLogsPath)
                results.append(await recorder.record(mutant, status: .unviable))
            }
        }

        let excludedIDs = Set(schemaBuildExcluded.map(\.id))
        let testableSchematizable = schematizable.filter { !excludedIDs.contains($0.id) }
        let targetedSuites = TargetedSuites.declared(in: deps.killerTestFileResolver.testFilePaths)

        if let artifact {
            var bundles: [TestBundle] = []
            var testFilter = configuration.build.testTarget
            if case .spm = configuration.build.projectType {
                (bundles, testFilter) = try await BaselineProbe(configuration: configuration, launcher: deps.launcher)
                    .probeTestBundles(in: sandbox)
            }
            let context = TestExecutionContext(
                artifact: artifact, sandbox: sandbox, pool: pool,
                configuration: configuration,
                bundles: bundles,
                testFilter: testFilter,
                targetedSuites: targetedSuites
            )
            results += try await runNormal(deps: deps, context: context, schematizable: testableSchematizable)
        } else if !testableSchematizable.isEmpty {
            results += try await runFallback(deps: deps, input: input, pool: pool)
        }

        results += try await runIncompatible(
            deps: deps, mutants: incompatible + reroutedToIncompatible, pool: pool,
            importStyle: input.importStyle, targetedSuites: targetedSuites
        )

        return results
    }

    static func requireObservedActivation(in results: [ExecutionResult]) throws {
        let measured = results.filter { $0.activated != nil }
        let killed = measured.filter { $0.status.isKill }

        guard !killed.isEmpty, !measured.contains(where: { $0.activated == true }) else { return }

        throw IntegrityError.activationNeverObserved(killed: killed.count)
    }

    private func allCached(
        mutants: [MutantDescriptor],
        cacheStore: CacheStore
    ) async -> [ExecutionResult]? {
        guard !mutants.isEmpty else { return nil }

        var results: [ExecutionResult] = []
        for mutant in mutants {
            guard let result = await cacheStore.cachedResult(for: mutant) else { return nil }
            results.append(result)
        }

        return results
    }

    private func buildArtifact(
        sandbox: Sandbox,
        input: RunnerInput,
        deps: ExecutionDeps
    ) async throws -> (BuildArtifact?, [MutantDescriptor]) {
        await deps.reporter.report(.buildStarted)
        let start = Date()
        let stage = BuildStage(launcher: deps.launcher)

        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            do {
                let artifact = try await stage.build(
                    sandbox: sandbox,
                    container: configuration.build.xcodeContainer,
                    scheme: scheme,
                    destination: destination,
                    timeout: configuration.build.buildTimeout
                )
                await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
                return (artifact, [])
            } catch BuildError.compilationFailed(_) {
                return (nil, [])
            }

        case .spm:
            do {
                let artifact = try await stage.buildSPM(
                    sandbox: sandbox,
                    timeout: configuration.build.buildTimeout
                )
                await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
                return (artifact, [])
            } catch BuildError.compilationFailed(let output) {
                return try await SchemaNarrower(
                    stage: stage, reporter: deps.reporter, buildTimeout: configuration.build.buildTimeout
                ).narrow(after: output, sandbox: sandbox, input: input, start: start)
            }
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
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        try await FallbackExecutor(deps: deps, configuration: configuration)
            .execute(input: input, pool: pool)
    }

    private func runIncompatible(
        deps: ExecutionDeps,
        mutants: [MutantDescriptor],
        pool: SimulatorPool,
        importStyle: ImportStyle,
        targetedSuites: [String: TargetedSuite]
    ) async throws -> [ExecutionResult] {
        try await IncompatibleMutantExecutor(
            deps: deps, sandboxFactory: environment.sandboxFactory, importStyle: importStyle,
            targetedSuites: targetedSuites
        )
        .execute(mutants, configuration: configuration, pool: pool)
    }

    private func rewriteForIncompatible(
        _ mutant: MutantDescriptor,
        rewriter: MutationRewriter,
        sourceCache: inout [String: String]
    ) -> MutantDescriptor? {
        let source: String
        if let cached = sourceCache[mutant.filePath] {
            source = cached
        } else {
            guard let loaded = try? String(contentsOfFile: mutant.filePath, encoding: .utf8) else {
                return nil
            }
            sourceCache[mutant.filePath] = loaded
            source = loaded
        }

        let content = rewriter.rewrite(source: source, applying: MutationPoint(mutant))
        guard content != source else { return nil }

        var rewritten = mutant
        rewritten.mutatedSourceContent = content
        return rewritten
    }

}

extension MutationPoint {
    init(_ descriptor: MutantDescriptor) {
        self.init(
            operatorIdentifier: descriptor.operatorIdentifier,
            filePath: descriptor.filePath,
            line: descriptor.line,
            column: descriptor.column,
            utf8Offset: descriptor.utf8Offset,
            originalText: descriptor.originalText,
            mutatedText: descriptor.mutatedText,
            replacement: descriptor.replacementKind,
            description: descriptor.description
        )
    }
}
