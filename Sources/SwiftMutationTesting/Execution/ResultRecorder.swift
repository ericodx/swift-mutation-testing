struct ResultRecorder: Sendable {
    let deps: ExecutionDeps
    let keepLogsPath: String?

    func cached(_ mutant: MutantDescriptor) async -> ExecutionResult? {
        guard let result = await deps.cacheStore.cachedResult(for: mutant) else { return nil }
        await finish(result)
        return result
    }

    func record(
        _ mutant: MutantDescriptor,
        status: ExecutionStatus,
        duration: Double = 0,
        output: String = "",
        activated: Bool? = nil,
        unconfirmedKiller: String? = nil
    ) async -> ExecutionResult {
        MutantLogWriter(directory: keepLogsPath)?
            .write(mutant: mutant, status: status, duration: duration, output: output, activated: activated)

        let killerTestFile = killerTestFile(for: status)
        await deps.cacheStore.store(
            status: status, for: MutantCacheKey.make(for: mutant), killerTestFile: killerTestFile,
            activated: activated, unconfirmedKiller: unconfirmedKiller, duration: duration
        )

        let result = ExecutionResult(
            descriptor: mutant, status: status, testDuration: duration, killerTestFile: killerTestFile,
            activated: activated, unconfirmedKiller: unconfirmedKiller
        )
        await finish(result)
        return result
    }

    func finish(_ result: ExecutionResult) async {
        let index = await deps.counter.increment()
        await deps.reporter.report(
            .mutantFinished(
                descriptor: result.descriptor, status: result.status, index: index, total: deps.counter.total)
        )
    }

    // MARK: - Private

    private func killerTestFile(for status: ExecutionStatus) -> String? {
        guard case .killed(let testName) = status else { return nil }
        return deps.killerTestFileResolver.resolve(testName: testName)
    }
}
