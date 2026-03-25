import Foundation

struct TestFilesHasher: Sendable {
    func hash(projectPath: String) -> String {
        let projectURL = URL(fileURLWithPath: projectPath)
        let paths = collectTestFilePaths(under: projectURL)
        let combined = paths.sorted().compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }.joined()
        return MutantCacheKey.hash(of: combined)
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
