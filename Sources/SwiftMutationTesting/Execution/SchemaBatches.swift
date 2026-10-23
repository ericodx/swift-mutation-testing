import Foundation
import SwiftParser

struct SchemaBatches: Sendable {
    static let mutantsPerFunction = 16

    var limit = Self.mutantsPerFunction

    private typealias Slice = (mutants: [MutantDescriptor], file: SchematizedFile)

    func split(_ input: RunnerInput) -> [RunnerInput] {
        var slicesByFile: [String: [Slice]] = [:]

        for file in input.schematizedFiles {
            let mutants = input.mutants.filter { $0.filePath == file.originalPath && $0.isSchematizable }
            guard let groups = slices(of: mutants, in: file), groups.count > 1 else { continue }

            let regenerated = groups.compactMap { group in
                SchemaNarrower.regeneratedSchema(
                    originalPath: file.originalPath, keeping: group, importStyle: input.importStyle
                ).map {
                    (mutants: group, file: SchematizedFile(originalPath: file.originalPath, schematizedContent: $0))
                }
            }
            guard regenerated.count == groups.count else { continue }
            slicesByFile[file.originalPath] = regenerated
        }

        guard !slicesByFile.isEmpty else { return [input] }

        let batchCount = slicesByFile.values.map(\.count).max() ?? 1
        var batches: [RunnerInput] = []

        for index in 0 ..< batchCount {
            var files: [SchematizedFile] = []
            var ids = Set<String>()

            for file in input.schematizedFiles {
                guard let slices = slicesByFile[file.originalPath] else {
                    if index == 0 { files.append(file) }
                    continue
                }
                guard index < slices.count else { continue }
                files.append(slices[index].file)
                ids.formUnion(slices[index].mutants.map(\.id))
            }

            let mutants = input.mutants.filter { mutant in
                guard slicesByFile[mutant.filePath] != nil, mutant.isSchematizable else { return index == 0 }
                return ids.contains(mutant.id)
            }

            batches.append(
                RunnerInput(
                    projectPath: input.projectPath,
                    projectType: input.projectType,
                    timeout: input.timeout,
                    concurrency: input.concurrency,
                    noCache: input.noCache,
                    schematizedFiles: files,
                    mutants: mutants,
                    importStyle: input.importStyle
                )
            )
        }

        return batches
    }

    // MARK: - Private

    private func slices(of mutants: [MutantDescriptor], in file: SchematizedFile) -> [[MutantDescriptor]]? {
        guard let content = try? String(contentsOfFile: file.originalPath, encoding: .utf8) else { return nil }

        let scopes = ParsedSource(
            file: SourceFile(path: file.originalPath, content: content),
            syntax: Parser.parse(source: content)
        ).functionScopes

        var slices: [[MutantDescriptor]] = []
        var rankByScope: [Int: Int] = [:]
        for mutant in MutantID.ordered(mutants, by: \.id) {
            let scope = scopes.innermostScope(containing: mutant.utf8Offset)?.bodyStartOffset ?? -1
            let rank = rankByScope[scope, default: 0]
            rankByScope[scope] = rank + 1

            let slice = rank / limit
            if slice == slices.count { slices.append([]) }
            slices[slice].append(mutant)
        }

        return slices
    }
}
