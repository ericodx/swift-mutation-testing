import Foundation

struct ApplicationVerifier: Sendable {
    var read: @Sendable (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }

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
                let content = read(sandbox.rootURL.path + original.dropFirst(projectRoot.count)),
                content != read(original)
            else { throw IntegrityError.schemaNotApplied(path: file.originalPath) }

            guard content.contains(SupportDeclarations.perFile(for: file.originalPath)) else {
                throw IntegrityError.supportMissing(path: file.originalPath)
            }

            written[original] = content
        }

        var files = OriginalFiles(read: read)
        let missing = mutants.filter { !isApplied($0, written: written, files: &files) }.map(Self.label)

        guard missing.isEmpty else { throw IntegrityError.mutantsNotApplied(mutants: missing) }
    }

    // MARK: - Private

    private static func label(_ mutant: MutantDescriptor) -> String {
        "\(mutant.id) (\(URL(fileURLWithPath: mutant.filePath).lastPathComponent):\(mutant.line))"
    }

    private struct OriginalFiles {
        init(read: @escaping (String) -> String?) {
            self.read = read
        }

        let read: (String) -> String?
        private var contents: [String: String?] = [:]
        private var canonicalPaths: [String: String] = [:]

        mutating func content(of path: String) -> String? {
            if let cached = contents[path] { return cached }
            let content = read(path)
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
