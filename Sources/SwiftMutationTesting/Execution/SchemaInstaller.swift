import Foundation

struct SchemaInstaller: Sendable {
    let sandbox: Sandbox
    let projectPath: String

    func install(_ files: [SchematizedFile], replacing previous: [SchematizedFile]) throws {
        let installing = Set(files.map { canonicalPath(of: $0.originalPath) })

        for file in previous where !installing.contains(canonicalPath(of: file.originalPath)) {
            let original = canonicalPath(of: file.originalPath)
            try SandboxLink.restore(at: try sandboxPath(of: original), to: original)
        }

        for file in files {
            let path = try sandboxPath(of: canonicalPath(of: file.originalPath))
            try LintSuppression.wrapping(file.schematizedContent).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Private

    private var projectRoot: String {
        URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().path
    }

    private func canonicalPath(of path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func sandboxPath(of canonicalOriginal: String) throws -> String {
        guard canonicalOriginal.hasPrefix(projectRoot + "/") else {
            throw IntegrityError.schemaNotApplied(path: canonicalOriginal)
        }
        return sandbox.rootURL.path + canonicalOriginal.dropFirst(projectRoot.count)
    }
}
