import Foundation

struct MutantExecutor: Sendable {

    init(configuration: RunnerConfiguration, launcher: any ProcessLaunching) {
        self.configuration = configuration
        self.launcher = launcher
    }

    private let configuration: RunnerConfiguration
    private let launcher: any ProcessLaunching

    private struct MutantRunContext {
        let deps: ExecutionDeps
        let input: RunnerInput
        let sandbox: Sandbox
        let pool: SimulatorPool
        let artifact: BuildArtifact?
        let schemaBuildExcluded: [MutantDescriptor]
        let testFilesHash: String
    }

    private struct RetryContext {
        let sandbox: Sandbox
        let input: RunnerInput
        let stage: BuildStage
        let deps: ExecutionDeps
        let start: Date
    }

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

        let (artifact, schemaBuildExcluded) = try await buildArtifact(sandbox: sandbox, input: input, deps: deps)
        let pool = try await makePool(launcher: launcher)
        try await pool.setUp()
        await reporter.report(.simulatorPoolReady(size: pool.size))

        let results: [ExecutionResult]
        do {
            results = try await runAllMutants(
                MutantRunContext(
                    deps: deps,
                    input: input,
                    sandbox: sandbox,
                    pool: pool,
                    artifact: artifact,
                    schemaBuildExcluded: schemaBuildExcluded,
                    testFilesHash: testFilesHash
                )
            )
        } catch {
            await pool.tearDown()
            try? sandbox.cleanup()
            throw error
        }

        await pool.tearDown()
        try? sandbox.cleanup()
        try await cacheStore.persist()

        return results
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
        let testFilesHash = context.testFilesHash
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
                let key = MutantCacheKey.make(for: mutant, testFilesHash: testFilesHash)
                await deps.cacheStore.store(status: .unviable, for: key)
                let index = await deps.counter.increment()
                await deps.reporter.report(
                    .mutantFinished(descriptor: mutant, status: .unviable, index: index, total: deps.counter.total))
                results.append(ExecutionResult(descriptor: mutant, status: .unviable, testDuration: 0))
            }
        }

        let excludedIDs = Set(schemaBuildExcluded.map(\.id))
        let testableSchematizable = schematizable.filter { !excludedIDs.contains($0.id) }

        if let artifact {
            if case .spm = configuration.build.projectType {
                await validateSPMBaseline(sandbox: sandbox, deps: deps)
            }
            let context = TestExecutionContext(
                artifact: artifact, sandbox: sandbox, pool: pool,
                configuration: configuration, testFilesHash: testFilesHash
            )
            results += try await runNormal(deps: deps, context: context, schematizable: testableSchematizable)
        } else if !testableSchematizable.isEmpty {
            results += try await runFallback(deps: deps, input: input, pool: pool, testFilesHash: testFilesHash)
        }

        results += try await runIncompatible(
            deps: deps, mutants: incompatible + reroutedToIncompatible, pool: pool, testFilesHash: testFilesHash
        )

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
                    scheme: scheme,
                    destination: destination,
                    timeout: configuration.build.timeout
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
                    timeout: configuration.build.timeout
                )
                await deps.reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
                return (artifact, [])
            } catch BuildError.compilationFailed(let output) {
                let retryCtx = RetryContext(
                    sandbox: sandbox, input: input,
                    stage: stage, deps: deps, start: start
                )
                let (artifact, excluded) = try await retryExcludingErrors(
                    output: output,
                    context: retryCtx,
                    alreadyExcluded: []
                )
                return (artifact, excluded)
            }
        }
    }

    private func retryExcludingErrors(
        output: String,
        context: RetryContext,
        alreadyExcluded: [MutantDescriptor]
    ) async throws -> (BuildArtifact?, [MutantDescriptor]) {
        let sandbox = context.sandbox
        let input = context.input
        let sandboxRoot = canonicalPath(sandbox.rootURL.path)
        let projectRoot = URL(fileURLWithPath: input.projectPath).resolvingSymlinksInPath().path
        let errorSandboxPaths = extractErrorPaths(from: output, sandboxRoot: sandboxRoot)
        let alreadyExcludedIDs = Set(alreadyExcluded.map(\.id))

        var newlyExcluded: [MutantDescriptor] = []

        for sandboxPath in errorSandboxPaths {
            let relative = String(sandboxPath.dropFirst(sandboxRoot.count))
            let originalPath = projectRoot + relative

            guard FileManager.default.fileExists(atPath: originalPath) else { continue }

            let mutantsInFile = input.mutants.filter { mutant in
                mutant.isSchematizable
                    && !alreadyExcludedIDs.contains(mutant.id)
                    && URL(fileURLWithPath: mutant.filePath).resolvingSymlinksInPath().path == originalPath
            }

            guard !mutantsInFile.isEmpty else { continue }

            newlyExcluded += excludeProblematicMutants(
                sandboxPath: sandboxPath,
                originalPath: originalPath,
                errorOutput: output,
                mutantsInFile: mutantsInFile
            )
        }

        guard !newlyExcluded.isEmpty else {
            return (nil, alreadyExcluded)
        }

        let allExcluded = alreadyExcluded + newlyExcluded

        do {
            let artifact = try await context.stage.buildSPM(
                sandbox: sandbox,
                timeout: configuration.build.timeout
            )
            await context.deps.reporter.report(
                .buildFinished(duration: Date().timeIntervalSince(context.start))
            )
            return (artifact, allExcluded)
        } catch BuildError.compilationFailed(let newOutput) {
            return try await retryExcludingErrors(
                output: newOutput,
                context: context,
                alreadyExcluded: allExcluded
            )
        }
    }

    private func extractErrorPaths(from output: String, sandboxRoot: String) -> Set<String> {
        Set(
            output.components(separatedBy: "\n").compactMap { line -> String? in
                guard line.hasPrefix(sandboxRoot) else { return nil }
                let path = line.components(separatedBy: ":").first ?? ""
                return path.hasSuffix(".swift") ? path : nil
            }
        )
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

    private func validateSPMBaseline(sandbox: Sandbox, deps: ExecutionDeps) async {
        var arguments = ["test", "--skip-build"]
        if let testTarget = configuration.build.testTarget {
            arguments += ["--filter", testTarget]
        }

        _ = try? await deps.launcher.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: arguments,
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: sandbox.rootURL,
                timeout: configuration.build.timeout
            )
        )
    }

    private func excludeProblematicMutants(
        sandboxPath: String,
        originalPath: String,
        errorOutput: String,
        mutantsInFile: [MutantDescriptor]
    ) -> [MutantDescriptor] {
        let errorLines = Set(
            errorOutput.components(separatedBy: "\n").compactMap { line -> Int? in
                guard line.hasPrefix(sandboxPath + ":") else { return nil }
                let remainder = String(line.dropFirst(sandboxPath.count + 1))
                return remainder.components(separatedBy: ":").first.flatMap { Int($0) }
            }
        )

        guard
            !errorLines.isEmpty,
            let content = try? String(contentsOfFile: sandboxPath, encoding: .utf8)
        else {
            restoreOriginal(sandboxPath: sandboxPath, originalPath: originalPath)
            return mutantsInFile
        }

        let lines = content.components(separatedBy: "\n")
        let mutantIDs = Set(mutantsInFile.map(\.id))
        var problematicIDs = Set<String>()

        for errorLine in errorLines {
            let lineIndex = errorLine - 1
            guard lineIndex >= 0, lineIndex < lines.count else { continue }
            var searchIndex = lineIndex
            while searchIndex >= 0 {
                let trimmed = lines[searchIndex].trimmingCharacters(in: .whitespaces)
                if let id = mutantCaseID(from: trimmed), mutantIDs.contains(id) {
                    problematicIDs.insert(id)
                    break
                }
                if trimmed == "default:" || trimmed.hasPrefix("switch ") { break }
                searchIndex -= 1
            }
        }

        guard !problematicIDs.isEmpty else {
            restoreOriginal(sandboxPath: sandboxPath, originalPath: originalPath)
            return mutantsInFile
        }

        let narrowed = removingCases(problematicIDs, from: lines)
        try? narrowed.write(toFile: sandboxPath, atomically: true, encoding: .utf8)

        let excluded = mutantsInFile.filter { problematicIDs.contains($0.id) }
        return excluded
    }

    private func restoreOriginal(sandboxPath: String, originalPath: String) {
        try? FileManager.default.removeItem(atPath: sandboxPath)
        try? FileManager.default.createSymbolicLink(atPath: sandboxPath, withDestinationPath: originalPath)
    }

    private func mutantCaseID(from trimmedLine: String) -> String? {
        let casePrefix = "case \""
        let caseSuffix = "\":"
        guard trimmedLine.hasPrefix(casePrefix), trimmedLine.hasSuffix(caseSuffix) else { return nil }
        let id = String(trimmedLine.dropFirst(casePrefix.count).dropLast(caseSuffix.count))
        return id.hasPrefix("swift-mutation-testing_") ? id : nil
    }

    private func removingCases(_ ids: Set<String>, from lines: [String]) -> String {
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let id = mutantCaseID(from: trimmed) {
                skipping = ids.contains(id)
                if !skipping { result.append(line) }
            } else if skipping {
                if trimmed == "default:" || mutantCaseID(from: trimmed) != nil {
                    skipping = false
                    result.append(line)
                }
            } else {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }

    private func rewriteForIncompatible(
        _ mutant: MutantDescriptor,
        rewriter: MutationRewriter,
        sourceCache: inout [String: String]
    ) -> MutantDescriptor? {
        let source: String
        if let cached = sourceCache[mutant.filePath] {
            source = cached
        } else if let loaded = try? String(contentsOfFile: mutant.filePath, encoding: .utf8) {
            sourceCache[mutant.filePath] = loaded
            source = loaded
        } else {
            return nil
        }

        let point = MutationPoint(
            operatorIdentifier: mutant.operatorIdentifier,
            filePath: mutant.filePath,
            line: mutant.line,
            column: mutant.column,
            utf8Offset: mutant.utf8Offset,
            originalText: mutant.originalText,
            mutatedText: mutant.mutatedText,
            replacement: mutant.replacementKind,
            description: mutant.description
        )

        let content = rewriter.rewrite(source: source, applying: point)
        guard content != source else { return nil }

        return MutantDescriptor(
            id: mutant.id,
            filePath: mutant.filePath,
            line: mutant.line,
            column: mutant.column,
            utf8Offset: mutant.utf8Offset,
            originalText: mutant.originalText,
            mutatedText: mutant.mutatedText,
            operatorIdentifier: mutant.operatorIdentifier,
            replacementKind: mutant.replacementKind,
            description: mutant.description,
            isSchematizable: mutant.isSchematizable,
            mutatedSourceContent: content
        )
    }

    private func canonicalPath(_ path: String) -> String {
        path.withCString { ptr in
            guard let resolved = realpath(ptr, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
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
