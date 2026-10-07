import Foundation

struct ApplicationVerifier: Sendable {
    func verify(
        schematizedFiles: [SchematizedFile],
        mutants: [MutantDescriptor],
        sandbox: Sandbox,
        projectPath: String
    ) throws {
        let projectRoot = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().path
        var written: [String: String] = [:]

        for file in schematizedFiles {
            let original = URL(fileURLWithPath: file.originalPath).resolvingSymlinksInPath().path

            guard
                original.hasPrefix(projectRoot + "/"),
                let content = try? String(
                    contentsOfFile: sandbox.rootURL.path + original.dropFirst(projectRoot.count), encoding: .utf8
                ),
                content != (try? String(contentsOfFile: original, encoding: .utf8))
            else { throw IntegrityError.schemaNotApplied(path: file.originalPath) }

            guard content.contains(SupportDeclarations.perFile(for: file.originalPath)) else {
                throw IntegrityError.supportMissing(path: file.originalPath)
            }

            written[original] = content
        }

        var files = OriginalFiles()
        let missing = mutants.filter { !isApplied($0, written: written, files: &files) }.map(Self.label)

        guard missing.isEmpty else { throw IntegrityError.mutantsNotApplied(mutants: missing) }
    }

    // MARK: - Private

    private static func label(_ mutant: MutantDescriptor) -> String {
        "\(mutant.id) (\(URL(fileURLWithPath: mutant.filePath).lastPathComponent):\(mutant.line))"
    }

    private struct OriginalFiles {
        private var contents: [String: String?] = [:]
        private var canonicalPaths: [String: String] = [:]

        mutating func content(of path: String) -> String? {
            if let cached = contents[path] { return cached }
            let content = try? String(contentsOfFile: path, encoding: .utf8)
            contents[path] = content
            return content
        }

        mutating func canonicalPath(of path: String) -> String {
            if let cached = canonicalPaths[path] { return cached }
            let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            canonicalPaths[path] = canonical
            return canonical
        }
    }

    private func isApplied(_ mutant: MutantDescriptor, written: [String: String], files: inout OriginalFiles) -> Bool {
        guard mutant.isSchematizable else {
            guard let mutated = mutant.mutatedSourceContent else { return false }
            return mutated != files.content(of: mutant.filePath)
        }

        return written[files.canonicalPath(of: mutant.filePath)]?.contains("case \"\(mutant.id)\":") == true
    }
}
