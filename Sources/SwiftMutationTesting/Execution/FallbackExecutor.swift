import Foundation

struct FallbackExecutor: Sendable {
    let deps: ExecutionDeps
    let configuration: RunnerConfiguration

    func execute(input: RunnerInput, pool: SimulatorPool, testFilesHash: String) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for file in input.schematizedFiles {
            results += try await processFile(file: file, input: input, pool: pool, testFilesHash: testFilesHash)
        }

        return results
    }

    private func processFile(
        file: SchematizedFile,
        input: RunnerInput,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        let fileMutants = input.mutants.filter { $0.filePath == file.originalPath && $0.isSchematizable }

        guard !fileMutants.isEmpty else { return [] }

        if let cached = await cachedResults(for: fileMutants, testFilesHash: testFilesHash) {
            return cached
        }

        let sandbox = try await SandboxFactory().create(
            projectPath: input.projectPath,
            schematizedFiles: [file],
            supportFileContent: input.supportFileContent
        )

        await deps.reporter.report(.fallbackBuildStarted(filePath: file.originalPath))

        guard case .xcode(let scheme, let destination) = configuration.build.projectType else {
            try? sandbox.cleanup()
            return await markUnviable(mutants: fileMutants, testFilesHash: testFilesHash)
        }

        let artifact: BuildArtifact
        do {
            artifact = try await BuildStage(launcher: deps.launcher).build(
                sandbox: sandbox,
                scheme: scheme,
                destination: destination,
                timeout: configuration.build.timeout
            )
            await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: true))
        } catch {
            await deps.reporter.report(.fallbackBuildFinished(filePath: file.originalPath, success: false))
            try? sandbox.cleanup()
            return await markUnviable(mutants: fileMutants, testFilesHash: testFilesHash)
        }

        let context = TestExecutionContext(
            artifact: artifact, sandbox: sandbox, pool: pool,
            configuration: configuration, testFilesHash: testFilesHash
        )

        let stageResults = try await TestExecutionStage(deps: deps).execute(mutants: fileMutants, in: context)
        try? sandbox.cleanup()
        return stageResults
    }

    private func cachedResults(for mutants: [MutantDescriptor], testFilesHash: String) async -> [ExecutionResult]? {
        guard !configuration.build.noCache else { return nil }

        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)
            guard let status = await deps.cacheStore.result(for: key) else { return nil }
            results.append(ExecutionResult(descriptor: mutant, status: status, testDuration: 0))
        }

        for result in results {
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(
                    descriptor: result.descriptor, status: result.status,
                    index: index, total: deps.counter.total))
        }

        return results
    }

    private func markUnviable(mutants: [MutantDescriptor], testFilesHash: String) async -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)
            await deps.cacheStore.store(status: .unviable, for: key)
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(descriptor: mutant, status: .unviable, index: index, total: deps.counter.total))
            results.append(ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0))
        }
        return results
    }
}
