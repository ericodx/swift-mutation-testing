import SwiftParser

struct ParsingStage: Sendable {
    func run(sourceFiles: [SourceFile]) async -> [ParsedSource] {
        await withTaskGroup(of: ParsedSource.self) { group in
            for file in sourceFiles {
                group.addTask {
                    ParsedSource(
                        file: file,
                        syntax: Parser.parse(source: file.content)
                    )
                }
            }

            var results: [ParsedSource] = []

            for await parsed in group {
                results.append(parsed)
            }

            return results
        }
    }
}
