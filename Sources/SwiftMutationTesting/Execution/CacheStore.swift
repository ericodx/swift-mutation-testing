import Foundation

private struct CacheEntry: Codable {
    let key: MutantCacheKey
    let status: ExecutionStatus
}

actor CacheStore {
    init(storePath: String) {
        self.storePath = storePath
        self.entries = [:]
    }

    private let storePath: String
    private var entries: [MutantCacheKey: ExecutionStatus]

    func result(for key: MutantCacheKey) -> ExecutionStatus? {
        entries[key]
    }

    func store(status: ExecutionStatus, for key: MutantCacheKey) {
        entries[key] = status
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: storePath) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: storePath))
        let loaded = try JSONDecoder().decode([CacheEntry].self, from: data)
        entries = Dictionary(uniqueKeysWithValues: loaded.map { ($0.key, $0.status) })
    }

    func persist() throws {
        let cacheEntries = entries.map { CacheEntry(key: $0.key, status: $0.value) }
        let data = try JSONEncoder().encode(cacheEntries)
        let url = URL(fileURLWithPath: storePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
