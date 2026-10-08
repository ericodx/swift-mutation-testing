import SwiftSyntax

struct MutantIndexingStage: Sendable {
    func run(mutationPoints: [MutationPoint], sources: [ParsedSource], projectPath: String) -> [IndexedMutationPoint] {
        let inOrder = zip(mutationPoints, mutationPoints.dropFirst()).allSatisfy {
            !MutationPoint.inSourceOrder($1, $0)
        }
        let sorted = inOrder ? mutationPoints : mutationPoints.sorted(by: MutationPoint.inSourceOrder)

        let scopesByPath = Dictionary(
            sources.map { ($0.file.path, $0.functionScopes) }, uniquingKeysWith: Uniquing.first
        )
        let syntaxByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.file.path, $0.syntax) })
        var ordinals: [[String]: Int] = [:]
        let paths = ProjectRelativePath.Resolver(projectPath: projectPath)

        return sorted.enumerated().map { index, mutation in
            let schematizable =
                scopesByPath[mutation.filePath]?.isSchematizable(utf8Offset: mutation.utf8Offset) ?? false
            let relativePath = paths.make(for: mutation.filePath)
            let declarationPath =
                syntaxByPath[mutation.filePath].map {
                    DeclarationPath.of(utf8Offset: mutation.utf8Offset, in: $0)
                } ?? DeclarationPath.topLevel
            let identity = [
                relativePath, declarationPath, mutation.operatorIdentifier, mutation.originalText, mutation.mutatedText,
            ]
            let ordinal = ordinals[identity, default: 0]
            ordinals[identity] = ordinal + 1

            return IndexedMutationPoint(
                index: index,
                mutation: mutation,
                isSchematizable: schematizable,
                fingerprint: MutantFingerprint.make(
                    relativePath: relativePath,
                    declarationPath: declarationPath,
                    mutation: mutation,
                    ordinal: ordinal
                )
            )
        }
    }
}
