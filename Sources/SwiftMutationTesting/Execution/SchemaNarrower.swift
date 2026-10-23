import Foundation
import SwiftParser

struct SchemaNarrower: Sendable {
    let stage: BuildStage
    let reporter: any ProgressReporter
    let buildTimeout: Double

    func narrow(
        after output: String,
        sandbox: Sandbox,
        input: RunnerInput,
        start: Date,
        alreadyExcluded: [MutantDescriptor] = []
    ) async throws -> (BuildArtifact?, [MutantDescriptor]) {
        let sandboxRoot = CanonicalPath.make(for: sandbox.rootURL.path)
        let projectRoot = URL(fileURLWithPath: input.projectPath).resolvingSymlinksInPath().path
        let errorSandboxPaths = Self.extractErrorPaths(from: output, sandboxRoot: sandboxRoot)
        let alreadyExcludedIDs = Set(alreadyExcluded.map(\.id))
        let schematizableByPath = Dictionary(
            grouping: input.mutants.filter { $0.isSchematizable && !alreadyExcludedIDs.contains($0.id) }
        ) { URL(fileURLWithPath: $0.filePath).resolvingSymlinksInPath().path }

        var newlyExcluded: [MutantDescriptor] = []

        for sandboxPath in errorSandboxPaths {
            let relative = String(sandboxPath.dropFirst(sandboxRoot.count))
            let originalPath = projectRoot + relative

            guard FileManager.default.fileExists(atPath: originalPath) else { continue }

            guard let mutantsInFile = schematizableByPath[originalPath], !mutantsInFile.isEmpty else { continue }

            newlyExcluded += try Self.excludeProblematicMutants(
                sandboxPath: sandboxPath,
                originalPath: originalPath,
                errorOutput: output,
                mutantsInFile: mutantsInFile,
                importStyle: input.importStyle
            )
        }

        guard !newlyExcluded.isEmpty else {
            return (nil, alreadyExcluded)
        }

        let allExcluded = alreadyExcluded + newlyExcluded
        await reporter.report(.schemaNarrowed(excludedCount: newlyExcluded.count))

        do {
            let artifact = try await stage.buildSPM(sandbox: sandbox, timeout: buildTimeout)
            await reporter.report(.buildFinished(duration: Date().timeIntervalSince(start)))
            return (artifact, allExcluded)
        } catch BuildError.compilationFailed(let newOutput) {
            return try await narrow(
                after: newOutput, sandbox: sandbox, input: input, start: start, alreadyExcluded: allExcluded
            )
        }
    }

    private static func extractErrorPaths(from output: String, sandboxRoot: String) -> Set<String> {
        Set(errorLocations(in: output, under: sandboxRoot).map(\.path))
    }

    private static func errorLocations(in output: String, under root: String) -> [(path: String, line: Int)] {
        output.components(separatedBy: "\n").compactMap { errorLocation(in: $0, under: root) }
    }

    private static func errorLocation(in line: String, under root: String) -> (path: String, line: Int)? {
        guard let rootRange = line.range(of: root) else { return nil }
        let fromRoot = line[rootRange.lowerBound...]

        guard let marker = fromRoot.range(of: ".swift:") else { return nil }
        let afterPath = fromRoot[marker.upperBound...]
        let digits = afterPath.prefix { $0.isNumber }

        guard let lineNumber = Int(digits), afterPath.dropFirst(digits.count).first == ":" else { return nil }

        return (String(fromRoot[..<marker.upperBound].dropLast()), lineNumber)
    }

    static func excludeProblematicMutants(
        sandboxPath: String,
        originalPath: String,
        errorOutput: String,
        mutantsInFile: [MutantDescriptor],
        importStyle: ImportStyle
    ) throws -> [MutantDescriptor] {
        let errorLines = Set(
            errorLocations(in: errorOutput, under: sandboxPath)
                .filter { $0.path == sandboxPath }
                .map(\.line)
        )

        guard
            !errorLines.isEmpty,
            let content = try? String(contentsOfFile: sandboxPath, encoding: .utf8)
        else {
            try SandboxLink.restore(at: sandboxPath, to: originalPath)
            return mutantsInFile
        }

        let lines = content.components(separatedBy: "\n")
        let mutantIDs = Set(mutantsInFile.map(\.id))
        var problematicIDs = Set<String>()

        for errorLine in errorLines {
            let lineIndex = errorLine - 1
            guard lineIndex >= 0, lineIndex < lines.count,
                let id = blamedMutantID(above: lineIndex, in: lines, among: mutantIDs)
            else { continue }
            problematicIDs.insert(id)
        }

        guard !problematicIDs.isEmpty else {
            try SandboxLink.restore(at: sandboxPath, to: originalPath)
            return mutantsInFile
        }

        let kept = mutantsInFile.filter { !problematicIDs.contains($0.id) }

        guard let narrowed = regeneratedSchema(originalPath: originalPath, keeping: kept, importStyle: importStyle)
        else {
            try SandboxLink.restore(at: sandboxPath, to: originalPath)
            return mutantsInFile
        }

        try LintSuppression.wrapping(narrowed).write(toFile: sandboxPath, atomically: true, encoding: .utf8)

        return mutantsInFile.filter { problematicIDs.contains($0.id) }
    }

    static func regeneratedSchema(
        originalPath: String, keeping mutants: [MutantDescriptor], importStyle: ImportStyle = .implicit
    ) -> String? {
        guard let content = try? String(contentsOfFile: originalPath, encoding: .utf8) else { return nil }

        let source = ParsedSource(
            file: SourceFile(path: originalPath, content: content),
            syntax: Parser.parse(source: content)
        )

        var entries: [(index: Int, point: MutationPoint)] = []

        for descriptor in mutants {
            guard let index = MutantID.index(of: descriptor.id) else { return nil }
            entries.append((index: index, point: MutationPoint(descriptor)))
        }

        let generation = SchemataGenerator().generate(source: source, mutations: entries, importStyle: importStyle)
        return generation.discarded.isEmpty ? generation.content : nil
    }

    private static func blamedMutantID(above index: Int, in lines: [String], among ids: Set<String>) -> String? {
        var skippedDispatches = 0

        for line in lines[...index].reversed() {
            if line == "default:" {
                skippedDispatches += 1
            } else if line.hasPrefix("switch \(SupportDeclarations.identifierPrefix)") {
                guard skippedDispatches > 0 else { return nil }
                skippedDispatches -= 1
            } else if skippedDispatches == 0, let id = mutantCaseID(from: line.trimmingCharacters(in: .whitespaces)),
                ids.contains(id)
            {
                return id
            }
        }

        return nil
    }

    private static func mutantCaseID(from trimmedLine: String) -> String? {
        let casePrefix = "case \""
        let caseSuffix = "\":"
        guard trimmedLine.hasPrefix(casePrefix), trimmedLine.hasSuffix(caseSuffix) else { return nil }
        let id = String(trimmedLine.dropFirst(casePrefix.count).dropLast(caseSuffix.count))
        return id.hasPrefix(MutantID.prefix) ? id : nil
    }
}
