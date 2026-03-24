import Foundation

struct FileDiscoveryStage: Sendable {
    private static let fixedExclusions: [String] = [
        "/Tests/",
        "/Mocks/",
        "/Stubs/",
        "/Fakes/",
        "/TestHelpers/",
        "/TestSupport/",
        "Tests.swift",
        "Mock.swift",
        "Spec.swift",
        "/.build/",
        "/.swift-mutation-testing-derived-data/",
        "/\(CacheStore.directoryName)/",
        "/DerivedData/",
    ]

    func run(input: DiscoveryInput) throws -> [SourceFile] {
        let url = URL(fileURLWithPath: input.sourcesPath)

        guard FileManager.default.fileExists(atPath: input.sourcesPath) else {
            throw FileDiscoveryError.sourcesPathNotFound(input.sourcesPath)
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw FileDiscoveryError.sourcesPathNotFound(input.sourcesPath)
        }

        var sourceFiles: [SourceFile] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            let path = fileURL.path

            guard !isExcluded(path: path, excludePatterns: input.excludePatterns) else {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            sourceFiles.append(SourceFile(path: path, content: content))
        }

        return sourceFiles
    }

    private func isExcluded(path: String, excludePatterns: [String]) -> Bool {
        for pattern in Self.fixedExclusions {
            if pattern.hasSuffix(".swift") {
                if path.hasSuffix(pattern) {
                    return true
                }
            } else if path.contains(pattern) {
                return true
            }
        }

        return excludePatterns.contains { path.contains($0) }
    }
}
