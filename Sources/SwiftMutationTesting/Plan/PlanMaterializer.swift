import Foundation

struct PlanMaterializer: Sendable {
    struct ExecutionOptions: Sendable {
        let timeout: Double
        let concurrency: Int
        let noCache: Bool
    }

    func materialize(
        plan: Plan, projectPath: String, execution: ExecutionOptions, mutants selection: [Plan.Mutant]? = nil
    ) async throws -> RunnerInput {
        let sources = try load(plan: plan, projectPath: projectPath)
        let parsed = await ParsingStage().run(sourceFiles: sources)
        return try materialize(
            plan: plan, projectPath: projectPath, sources: parsed, execution: execution, mutants: selection
        )
    }

    func materialize(
        plan: Plan,
        projectPath: String,
        sources: [ParsedSource],
        execution: ExecutionOptions,
        mutants selection: [Plan.Mutant]? = nil
    ) throws -> RunnerInput {
        let selected = Set((selection ?? plan.mutants).map(\.fingerprint))
        let sourceByRelativePath = Uniquing.keepingFirst(
            sources.map { (Planner.relative($0.file.path, to: projectPath), $0) }
        )
        let indexed: [IndexedMutationPoint] = try plan.mutants.enumerated().compactMap { index, mutant in
            guard selected.contains(mutant.fingerprint) else { return nil }
            guard let source = sourceByRelativePath[mutant.file] else {
                throw PlanError.missingFile(file: mutant.file)
            }
            return IndexedMutationPoint(
                index: index,
                mutation: MutationPoint(
                    operatorIdentifier: mutant.operatorIdentifier,
                    filePath: source.file.path,
                    line: mutant.line,
                    column: mutant.column,
                    utf8Offset: mutant.utf8Start,
                    originalText: mutant.original,
                    mutatedText: mutant.replacement,
                    replacement: mutant.replacementKind,
                    description: mutant.description
                ),
                isSchematizable: mutant.schematizable,
                fingerprint: mutant.fingerprint
            )
        }

        let (schematizedFiles, schematizable) = SchematizationStage().run(indexed: indexed, sources: sources)
        let incompatible = IncompatibleRewritingStage().run(indexed: indexed, sources: sources)
        let descriptors = MutantID.ordered(schematizable + incompatible, by: \.id)

        guard let projectType = plan.project.projectType else {
            throw PlanError.unknownProjectType(plan.project.type)
        }

        return RunnerInput(
            projectPath: projectPath,
            projectType: projectType,
            timeout: execution.timeout,
            concurrency: execution.concurrency,
            noCache: execution.noCache,
            schematizedFiles: schematizedFiles,
            mutants: descriptors,
            importStyle: ImportStyle.of(sources)
        )
    }

    func load(plan: Plan, projectPath: String) throws -> [SourceFile] {
        var sources: [SourceFile] = []
        for file in plan.files {
            let path = Self.absolute(file.path, in: projectPath)
            guard FileManager.default.fileExists(atPath: path) else {
                throw PlanError.missingFile(file: file.path)
            }
            let content: String
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                throw PlanError.unreadableFile(file: file.path, reason: error.localizedDescription)
            }
            guard MutantCacheKey.hash(of: content) == file.sha256 else {
                throw PlanError.stale(file: file.path)
            }
            sources.append(SourceFile(path: path, content: content))
        }

        let bytesByFile = Dictionary(
            uniqueKeysWithValues: zip(plan.files.map(\.path), sources.map { Array($0.content.utf8) })
        )
        for mutant in plan.mutants {
            guard let bytes = bytesByFile[mutant.file] else { throw PlanError.missingFile(file: mutant.file) }
            guard
                mutant.utf8Start >= 0, mutant.utf8End <= bytes.count, mutant.utf8Start <= mutant.utf8End,
                Array(mutant.original.utf8) == Array(bytes[mutant.utf8Start ..< mutant.utf8End])
            else {
                throw PlanError.corrupt(fingerprint: mutant.fingerprint, file: mutant.file)
            }
        }

        return sources
    }

    static func fileHashes(of plan: Plan) -> [String: String] {
        Uniquing.keepingFirst(plan.files.map { ($0.path, $0.sha256) })
    }

    static func descriptor(
        of mutant: Plan.Mutant, at index: Int, in plan: Plan, projectPath: String
    ) -> MutantDescriptor {
        descriptor(of: mutant, at: index, fileHashes: fileHashes(of: plan), projectPath: projectPath)
    }

    static func descriptor(
        of mutant: Plan.Mutant, at index: Int, fileHashes: [String: String], projectPath: String
    ) -> MutantDescriptor {
        MutantDescriptor(
            id: MutantID.make(index: index),
            filePath: absolute(mutant.file, in: projectPath),
            line: mutant.line,
            column: mutant.column,
            utf8Offset: mutant.utf8Start,
            originalText: mutant.original,
            mutatedText: mutant.replacement,
            operatorIdentifier: mutant.operatorIdentifier,
            replacementKind: mutant.replacementKind,
            description: mutant.description,
            isSchematizable: mutant.schematizable,
            mutatedSourceContent: nil,
            sourceContentHash: fileHashes[mutant.file] ?? "",
            fingerprint: mutant.fingerprint
        )
    }

    static func absolute(_ relativePath: String, in projectPath: String) -> String {
        let root = URL(fileURLWithPath: CanonicalPath.make(for: projectPath))
        return relativePath == "." ? root.path : root.appendingPathComponent(relativePath).path
    }
}
