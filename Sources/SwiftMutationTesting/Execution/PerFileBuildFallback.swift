import Foundation

struct PerFileBuildFallback: Sendable {
    let launcher: any ProcessLaunching
    let sandboxFactory: SandboxFactory
    let cacheStore: CacheStore
    let reporter: any ProgressReporter

    func execute(
        input: RunnerInput,
        configuration: RunnerConfiguration,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for file in input.schematizedFiles {
            let fileResults = try await processFile(
                file: file,
                input: input,
                configuration: configuration,
                pool: pool,
                testFilesHash: testFilesHash
            )
            results += fileResults
        }

        return results
    }

    private func processFile(
        file: SchematizedFile,
        input: RunnerInput,
        configuration: RunnerConfiguration,
        pool: SimulatorPool,
        testFilesHash: String
    ) async throws -> [ExecutionResult] {
        let mutants = input.mutants.filter { $0.filePath == file.originalPath && $0.isSchematizable }

        guard !mutants.isEmpty else { return [] }

        if !configuration.noCache {
            var cached: [ExecutionResult] = []
            for mutant in mutants {
                let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)
                guard let status = await cacheStore.result(for: key) else { break }
                cached.append(ExecutionResult(descriptor: mutant, status: status, testDuration: 0))
            }
            if cached.count == mutants.count {
                for result in cached { await reporter.report(.mutantTested(result: result)) }
                return cached
            }
        }

        let sandbox = try await sandboxFactory.create(
            projectPath: configuration.projectPath,
            schematizedFiles: [file],
            supportFileContent: input.supportFileContent
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
            try? sandbox.cleanup()
            return await markAllUnviable(mutants: mutants, testFilesHash: testFilesHash)
        }

        let context = TestExecutionContext(
            artifact: artifact,
            sandbox: sandbox,
            pool: pool,
            configuration: configuration,
            testFilesHash: testFilesHash
        )

        let stage = TestExecutionStage(launcher: launcher, cacheStore: cacheStore, reporter: reporter)
        let results = try await stage.execute(mutants: mutants, in: context)
        try? sandbox.cleanup()
        return results
    }

    private func markAllUnviable(
        mutants: [MutantDescriptor],
        testFilesHash: String
    ) async -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        for mutant in mutants {
            let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)
            await cacheStore.store(status: .unviable, for: key)
            let result = ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0)
            await reporter.report(.mutantTested(result: result))
            results.append(result)
        }
        return results
    }
}
