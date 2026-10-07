struct FallbackExecutor: Sendable {
    let deps: ExecutionDeps
    let configuration: RunnerConfiguration

    private var recorder: ResultRecorder {
        ResultRecorder(deps: deps, keepLogsPath: configuration.reporting.keepLogsPath)
    }

    func execute(input: RunnerInput, pool: SimulatorPool) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for file in input.schematizedFiles {
            results += try await processFile(file: file, input: input, pool: pool)
        }

        return results
    }

    private func processFile(
        file: SchematizedFile,
        input: RunnerInput,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        let fileMutants = input.mutants.filter { $0.filePath == file.originalPath && $0.isSchematizable }

        guard !fileMutants.isEmpty else { return [] }

        if let cached = await cachedResults(for: fileMutants) {
            return cached
        }

        let sandbox = try await SandboxFactory().create(
            projectPath: input.projectPath,
            schematizedFiles: [file]
        )
        defer { sandbox.release(keepingFor: configuration.build.reproduction) }

        try ApplicationVerifier().verify(
            schematizedFiles: [file], mutants: fileMutants, sandbox: sandbox, projectPath: input.projectPath
        )

        await deps.reporter.report(.fallbackBuildStarted(filePath: file.originalPath))

        let artifact: BuildArtifact
        do {
            artifact = try await build(sandbox)
            await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: true))
        } catch let error as BuildError where Self.isVerdict(error) {
            await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: false))
            return await markBuildFailure(error, mutants: fileMutants)
        }

        let selection = TestTargetSelection.make(
            target: configuration.build.testTarget, bundleURLs: TestBundleInvocation.bundleURLs(in: sandbox)
        )
        let context = TestExecutionContext(
            artifact: artifact, sandbox: sandbox, pool: pool,
            configuration: configuration,
            bundles: selection.bundleURLs.map { TestBundle(url: $0, libraries: TestBundle.allLibraries) },
            testFilter: selection.filter
        )

        return try await TestExecutionStage(deps: deps).execute(mutants: fileMutants, in: context)
    }

    private func cachedResults(for mutants: [MutantDescriptor]) async -> [ExecutionResult]? {
        var results: [ExecutionResult] = []
        for mutant in mutants {
            guard let result = await deps.cacheStore.cachedResult(for: mutant) else { return nil }
            results.append(result)
        }

        for result in results {
            await recorder.finish(result)
        }

        return results
    }

    private func build(_ sandbox: Sandbox) async throws -> BuildArtifact {
        let stage = BuildStage(launcher: deps.launcher)
        switch configuration.build.projectType {
        case .xcode(let scheme, let destination):
            return try await stage.build(
                sandbox: sandbox,
                container: configuration.build.xcodeContainer,
                scheme: scheme,
                destination: destination,
                timeout: configuration.build.buildTimeout
            )

        case .spm:
            return try await stage.buildSPM(sandbox: sandbox, timeout: configuration.build.buildTimeout)
        }
    }

    private static func isVerdict(_ error: BuildError) -> Bool {
        switch error {
        case .compilationFailed, .timedOut: true
        case .xctestrunNotFound: false
        }
    }

    private func markBuildFailure(
        _ error: BuildError,
        mutants: [MutantDescriptor]
    ) async -> [ExecutionResult] {
        let status: ExecutionStatus = if case .timedOut = error { .timeout } else { .unviable }

        var results: [ExecutionResult] = []
        for mutant in mutants {
            results.append(await recorder.record(mutant, status: status, output: error.localizedDescription))
        }
        return results
    }
}
