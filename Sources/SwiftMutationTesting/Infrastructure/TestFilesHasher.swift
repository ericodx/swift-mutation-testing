import Foundation

struct TestFilesHasher: Sendable {
    func hash(projectPath: String) -> String {
        let perFile = hashPerFile(projectPath: projectPath)
        let combined = perFile.keys.sorted().compactMap { perFile[$0] }.joined()
        return MutantCacheKey.hash(of: combined)
    }

    func hashPerFile(projectPath: String) -> [String: String] {
        let projectURL = URL(fileURLWithPath: projectPath)
        let resolvedPrefix = projectURL.resolvingSymlinksInPath().path
        let paths = collectTestFilePaths(under: projectURL)
        var result: [String: String] = [:]

        for path in paths.sorted() {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path

            let relativePath: String
            if resolvedPath.hasPrefix(resolvedPrefix) {
                relativePath = String(resolvedPath.dropFirst(resolvedPrefix.count).drop(while: { $0 == "/" }))
            } else {
                relativePath = path
            }

            result[relativePath] = MutantCacheKey.hash(of: content)
        }

        return result
    }

    func testFilePaths(projectPath: String) -> [String] {
        collectTestFilePaths(under: URL(fileURLWithPath: projectPath))
    }

    private func collectTestFilePaths(under directory: URL) -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }

            let isInTestsDir = url.pathComponents.contains { $0.hasSuffix("Tests") }
            let isTestFile = url.lastPathComponent.hasSuffix("Tests.swift")

            if isInTestsDir || isTestFile {
                paths.append(url.path)
            }
        }

        return paths
    }
}
