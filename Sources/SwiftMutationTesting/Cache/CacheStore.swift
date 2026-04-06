import Foundation

actor CacheStore {

    init(storePath: String) {
        self.storePath = storePath
        self.entries = [:]
        self.killerTestFiles = [:]
    }

    static let directoryName = ".swift-mutation-testing-cache"

    private let storePath: String
    private var entries: [MutantCacheKey: ExecutionStatus]
    private var killerTestFiles: [MutantCacheKey: String]

    private var metadataPath: String {
        let url = URL(fileURLWithPath: storePath)
        return url.deletingLastPathComponent().appendingPathComponent("metadata.json").path
    }

    private struct CacheEntry: Codable {
        let key: MutantCacheKey
        let status: ExecutionStatus
        let killerTestFile: String?
    }

    struct CacheMetadata: Codable, Sendable {
        let testFileHashes: [String: String]
    }

    func result(for key: MutantCacheKey) -> ExecutionStatus? {
        entries[key]
    }

    func killerTestFile(for key: MutantCacheKey) -> String? {
        killerTestFiles[key]
    }

    func store(status: ExecutionStatus, for key: MutantCacheKey, killerTestFile: String? = nil) {
        entries[key] = status
        if let killerTestFile {
            killerTestFiles[key] = killerTestFile
        }
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: storePath) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: storePath))
        let loaded = try JSONDecoder().decode([CacheEntry].self, from: data)
        entries = [:]
        for entry in loaded {
            entries[entry.key] = entry.status
        }
        killerTestFiles = [:]
        for entry in loaded {
            if let file = entry.killerTestFile {
                killerTestFiles[entry.key] = file
            }
        }
    }

    func persist() throws {
        let cacheEntries = entries.map {
            CacheEntry(key: $0.key, status: $0.value, killerTestFile: killerTestFiles[$0.key])
        }
        let data = try JSONEncoder().encode(cacheEntries)
        let url = URL(fileURLWithPath: storePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func loadMetadata() throws -> CacheMetadata? {
        let url = URL(fileURLWithPath: metadataPath)
        guard FileManager.default.fileExists(atPath: metadataPath) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CacheMetadata.self, from: data)
    }

    func persistMetadata(_ metadata: CacheMetadata) throws {
        let data = try JSONEncoder().encode(metadata)
        let url = URL(fileURLWithPath: metadataPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func invalidate(diff: TestFileDiff) {
        guard diff.hasChanges else { return }

        let changedFiles = diff.modified.union(diff.removed)

        for (key, status) in entries {
            switch status {
            case .unviable, .killedByCrash:
                continue

            case .killed:
                guard let file = killerTestFiles[key] else {
                    entries.removeValue(forKey: key)
                    killerTestFiles.removeValue(forKey: key)
                    continue
                }

                if changedFiles.contains(file) {
                    entries.removeValue(forKey: key)
                    killerTestFiles.removeValue(forKey: key)
                }

            case .survived, .noCoverage, .timeout:
                entries.removeValue(forKey: key)
                killerTestFiles.removeValue(forKey: key)
            }
        }
    }

    func changedTestFiles(current: [String: String]) throws -> TestFileDiff {
        guard let stored = try loadMetadata() else {
            return TestFileDiff(
                added: Set(current.keys),
                modified: [],
                removed: []
            )
        }

        let storedKeys = Set(stored.testFileHashes.keys)
        let currentKeys = Set(current.keys)

        let added = currentKeys.subtracting(storedKeys)
        let removed = storedKeys.subtracting(currentKeys)

        var modified: Set<String> = []
        for key in storedKeys.intersection(currentKeys) where stored.testFileHashes[key] != current[key] {
            modified.insert(key)
        }

        return TestFileDiff(added: added, modified: modified, removed: removed)
    }

}
