import Foundation

struct PlanJournal: Sendable {
    struct Entry: Sendable, Codable, Equatable {
        let fingerprint: String
        let status: ExecutionStatus
        let killerTestFile: String?
        let activated: Bool?
        let duration: Double
    }

    let path: String
    private let fingerprintByKey: [MutantCacheKey: String]
    private let warning: OnceWarning

    init(path: String, mutants: [MutantDescriptor], warning: OnceWarning = OnceWarning()) {
        self.path = path
        self.warning = warning
        fingerprintByKey = Dictionary(
            mutants.map { (MutantCacheKey.make(for: $0), $0.fingerprint) }, uniquingKeysWith: { first, _ in first }
        )
    }

    static func path(projectPath: String, planSha256: String, shard: Shard?) -> String {
        let name = shard.map { "\(planSha256)-\($0.index)-of-\($0.count)" } ?? planSha256
        return URL(fileURLWithPath: projectPath)
            .appendingPathComponent(CacheStore.directoryName)
            .appendingPathComponent("plans")
            .appendingPathComponent("\(name).jsonl").path
    }

    func record(
        status: ExecutionStatus, for key: MutantCacheKey, killerTestFile: String?, activated: Bool?, duration: Double
    ) {
        guard let fingerprint = fingerprintByKey[key] else { return }
        let entry = Entry(
            fingerprint: fingerprint, status: status, killerTestFile: killerTestFile, activated: activated,
            duration: duration
        )
        do {
            try JSONLines.append(entry, to: path)
        } catch {
            warning(JSONLines.failureWarning(for: path, error: error))
        }
    }

    static func entries(at path: String) -> [String: Entry] {
        Dictionary(
            JSONLines.read(Entry.self, from: path).map { ($0.fingerprint, $0) }, uniquingKeysWith: { _, last in last }
        )
    }

    static func remove(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
