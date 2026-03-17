import Foundation

actor CacheStore {
    init(cacheURL: URL) {
        self.cacheURL = cacheURL
        self.entries = (try? Self.load(from: cacheURL)) ?? [:]
    }

    private let cacheURL: URL
    private var entries: [String: ExecutionStatus]

    private static func load(from url: URL) throws -> [String: ExecutionStatus] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: ExecutionStatus].self, from: data)
    }

    private static func save(_ entries: [String: ExecutionStatus], to url: URL) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: .atomic)
    }

    func result(for key: MutantCacheKey) -> ExecutionStatus? {
        entries[key.value]
    }

    func store(_ status: ExecutionStatus, for key: MutantCacheKey) {
        entries[key.value] = status
        try? Self.save(entries, to: cacheURL)
    }
}
