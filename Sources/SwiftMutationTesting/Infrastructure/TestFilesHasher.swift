import Foundation

struct TestFilesHasher: Sendable {

    typealias FileEnumerator = (URL) -> FileManager.DirectoryEnumerator?

    static func defaultEnumerator(_ directory: URL) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    }

    struct Snapshot: Sendable {
        let paths: [String]
        let contents: [String: String]
        let hashes: [String: String]
    }

    func snapshot(projectPath: String, enumerate: FileEnumerator = Self.defaultEnumerator) -> Snapshot {
        let paths = collectTestFilePaths(under: URL(fileURLWithPath: projectPath), enumerate: enumerate)
        var contents: [String: String] = [:]
        var hashes: [String: String] = [:]

        for path in paths.sorted() {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            contents[path] = content
            hashes[ProjectRelativePath.make(for: path, in: projectPath)] = MutantCacheKey.hash(of: content)
        }

        return Snapshot(paths: paths, contents: contents, hashes: hashes)
    }

    func hashPerFile(
        projectPath: String,
        enumerate: FileEnumerator = Self.defaultEnumerator
    ) -> [String: String] {
        snapshot(projectPath: projectPath, enumerate: enumerate).hashes
    }

    func testFilePaths(projectPath: String, enumerate: FileEnumerator = Self.defaultEnumerator) -> [String] {
        collectTestFilePaths(under: URL(fileURLWithPath: projectPath), enumerate: enumerate)
    }

    private func collectTestFilePaths(under directory: URL, enumerate: FileEnumerator) -> [String] {
        guard let enumerator = enumerate(directory) else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }

            let relativePath = ProjectRelativePath.make(for: url.path, in: directory.path)
            let isInTestsDir = relativePath.split(separator: "/").dropLast().contains { $0.hasSuffix("Tests") }
            let isTestFile = url.lastPathComponent.hasSuffix("Tests.swift")

            if isInTestsDir || isTestFile {
                paths.append(url.path)
            }
        }

        return paths
    }
}
