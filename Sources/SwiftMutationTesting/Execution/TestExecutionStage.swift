import Foundation

private struct TestLaunchResult {
    let exitCode: Int32
    let output: String
    let xcresultPath: String
    let duration: Double
}

struct TestExecutionStage: Sendable {
    let launcher: any ProcessLaunching
    let cacheStore: CacheStore
    let reporter: any ProgressReporter
    let counter: MutationCounter

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        let concurrency = context.configuration.concurrency

        try await withThrowingTaskGroup(of: ExecutionResult.self) { group in
            var activeTasks = 0
            var iterator = mutants.makeIterator()

            while activeTasks < concurrency, let mutant = iterator.next() {
                let key = MutantCacheKey.make(for: mutant, testFilesHash: context.testFilesHash)
                group.addTask { try await self.run(mutant: mutant, key: key, in: context) }
                activeTasks += 1
            }

            for try await result in group {
                results.append(result)
                if let next = iterator.next() {
                    let key = MutantCacheKey.make(for: next, testFilesHash: context.testFilesHash)
                    group.addTask { try await self.run(mutant: next, key: key, in: context) }
                }
            }
        }

        return results
    }

    private func run(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        if !context.configuration.noCache, let cached = await cacheStore.result(for: key) {
            let result = ExecutionResult(descriptor: mutant, status: cached, testDuration: 0)
            let index = await counter.increment()
            await reporter.report(
                .mutantFinished(descriptor: mutant, status: cached, index: index, total: counter.total))
            return result
        }

        guard let plistData = context.artifact.plist.activating(mutant.id) else {
            let result = ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0)
            await cacheStore.store(status: .unviable, for: key)
            let index = await counter.increment()
            await reporter.report(
                .mutantFinished(descriptor: mutant, status: .unviable, index: index, total: counter.total))
            return result
        }

        let slot = try await context.pool.acquire()
        let launched: TestLaunchResult
        do {
            launched = try await launch(plistData: plistData, slot: slot, in: context)
        } catch {
            await context.pool.release(slot)
            throw error
        }
        await context.pool.release(slot)

        let outcome = try await ResultParser(launcher: launcher).parse(
            exitCode: launched.exitCode,
            output: launched.output,
            xcresultPath: launched.xcresultPath,
            timeout: context.configuration.timeout
        )

        let status = outcome.asExecutionStatus
        let result = ExecutionResult(descriptor: mutant, status: status, testDuration: launched.duration)
        await cacheStore.store(status: status, for: key)
        let index = await counter.increment()
        await reporter.report(.mutantFinished(descriptor: mutant, status: status, index: index, total: counter.total))
        return result
    }

    private func launch(
        plistData: Data,
        slot: SimulatorSlot,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        let xctestrunURL = context.artifact.xctestrunURL.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).xctestrun")
        let xcresultPath = context.sandbox.rootURL
            .appendingPathComponent("\(UUID().uuidString).xcresult").path

        defer {
            try? FileManager.default.removeItem(at: xctestrunURL)
            try? FileManager.default.removeItem(atPath: xcresultPath)
        }

        try plistData.write(to: xctestrunURL)

        var arguments = [
            "test-without-building",
            "-xctestrun", xctestrunURL.path,
            "-destination", slot.destination,
            "-resultBundlePath", xcresultPath,
            "-derivedDataPath", context.artifact.derivedDataPath,
        ]

        if let testTarget = context.configuration.testTarget {
            arguments += ["-only-testing", testTarget]
        }

        let start = Date()
        let captured = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: arguments,
            environment: nil,
            workingDirectoryURL: context.sandbox.rootURL,
            timeout: context.configuration.timeout
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }
}
