import SwiftSyntax

struct MutantIndexingStage: Sendable {
    func run(mutationPoints: [MutationPoint], sources: [ParsedSource]) -> [IndexedMutationPoint] {
        let sorted = mutationPoints.sorted {
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            return $0.utf8Offset < $1.utf8Offset
        }

        let visitors = buildVisitors(for: sources)

        return sorted.enumerated().map { index, mutation in
            let schematizable = visitors[mutation.filePath]?.isSchematizable(utf8Offset: mutation.utf8Offset) ?? false
            return IndexedMutationPoint(index: index, mutation: mutation, isSchematizable: schematizable)
        }
    }

    private func buildVisitors(for sources: [ParsedSource]) -> [String: TypeScopeVisitor] {
        var visitors: [String: TypeScopeVisitor] = [:]
        for source in sources {
            let visitor = TypeScopeVisitor()
            visitor.walk(source.syntax)
            visitors[source.file.path] = visitor
        }
        return visitors
    }
}
