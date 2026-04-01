import Foundation

struct TestExecutionStage: Sendable {
    let deps: ExecutionDeps

    func execute(
        mutants: [MutantDescriptor],
        in context: TestExecutionContext
    ) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        let concurrency = context.configuration.build.concurrency

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
        if !context.configuration.build.noCache, let cached = await deps.cacheStore.result(for: key) {
            let result = ExecutionResult(descriptor: mutant, status: cached, testDuration: 0)
            let index = await deps.counter.increment()
            await deps.reporter.report(
                .mutantFinished(descriptor: mutant, status: cached, index: index, total: deps.counter.total))
            return result
        }

        guard let plist = context.artifact.plist else {
            return try await runSPM(mutant: mutant, key: key, in: context)
        }

        let plistData = plist.activating(mutant.id)
        let slot = try await context.pool.acquire()
        let launched: TestLaunchResult
        do {
            launched = try await launch(plistData: plistData, slot: slot, in: context)
        } catch {
            await context.pool.release(slot)
            throw error
        }
        await context.pool.release(slot)

        let outcome = try await ResultParser(launcher: deps.launcher).parse(
            exitCode: launched.exitCode,
            output: launched.output,
            xcresultPath: launched.xcresultPath,
            timeout: context.configuration.build.timeout
        )
        try? FileManager.default.removeItem(atPath: launched.xcresultPath)

        let status = outcome.asExecutionStatus
        let result = ExecutionResult(descriptor: mutant, status: status, testDuration: launched.duration)
        await deps.cacheStore.store(status: status, for: key)
        let index = await deps.counter.increment()
        await deps.reporter.report(.mutantFinished(descriptor: mutant, status: status, index: index, total: deps.counter.total))
        return result
    }

    private func runSPM(
        mutant: MutantDescriptor,
        key: MutantCacheKey,
        in context: TestExecutionContext
    ) async throws -> ExecutionResult {
        let slot = try await context.pool.acquire()
        let launched: TestLaunchResult
        do {
            launched = try await launchSPM(mutant: mutant, in: context)
        } catch {
            await context.pool.release(slot)
            throw error
        }
        await context.pool.release(slot)

        let outcome = SPMResultParser().parse(exitCode: launched.exitCode, output: launched.output)
        let status = outcome.asExecutionStatus
        if status == .unviable {
            let snippet = String(launched.output.prefix(300)).replacingOccurrences(of: "\n", with: "↵")
            fputs("[xmr] unviable mutant=\(mutant.id) file=\(URL(fileURLWithPath: mutant.filePath).lastPathComponent) exitCode=\(launched.exitCode) output=\(snippet)\n", stderr)
        }
        let result = ExecutionResult(descriptor: mutant, status: status, testDuration: launched.duration)
        await deps.cacheStore.store(status: status, for: key)
        let index = await deps.counter.increment()
        await deps.reporter.report(.mutantFinished(descriptor: mutant, status: status, index: index, total: deps.counter.total))
        return result
    }

    private func launchSPM(
        mutant: MutantDescriptor,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        var arguments = ["test", "--skip-build"]

        if let testTarget = context.configuration.build.testTarget {
            arguments += ["--filter", testTarget]
        }

        let start = Date()
        let captured = try await deps.launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: ["__SWIFT_MUTATION_TESTING_ACTIVE": mutant.id],
            workingDirectoryURL: context.sandbox.rootURL,
            timeout: context.configuration.build.timeout
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: "",
            duration: Date().timeIntervalSince(start)
        )
    }

    private func launch(
        plistData: Data,
        slot: SimulatorSlot,
        in context: TestExecutionContext
    ) async throws -> TestLaunchResult {
        let baseURL =
            context.artifact.xctestrunURL?.deletingLastPathComponent()
            ?? context.sandbox.rootURL
        let xctestrunURL = baseURL.appendingPathComponent("\(UUID().uuidString).xctestrun")
        let xcresultPath = context.sandbox.rootURL
            .appendingPathComponent("\(UUID().uuidString).xcresult").path

        defer { try? FileManager.default.removeItem(at: xctestrunURL) }

        try plistData.write(to: xctestrunURL)

        var arguments = [
            "test-without-building",
            "-xctestrun", xctestrunURL.path,
            "-destination", slot.destination,
            "-resultBundlePath", xcresultPath,
            "-derivedDataPath", context.artifact.derivedDataPath,
        ]

        if let testTarget = context.configuration.build.testTarget {
            arguments += ["-only-testing", testTarget]
        }

        let start = Date()
        let captured = try await deps.launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: arguments,
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: context.sandbox.rootURL,
            timeout: context.configuration.build.timeout
        )

        return TestLaunchResult(
            exitCode: captured.exitCode,
            output: captured.output,
            xcresultPath: xcresultPath,
            duration: Date().timeIntervalSince(start)
        )
    }
}
