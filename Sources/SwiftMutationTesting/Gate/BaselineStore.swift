import Foundation

struct BaselineStore: Sendable {
    func read(from path: String) throws -> Baseline {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try VersionedJSON.read(
            Baseline.self,
            from: path,
            version: Baseline.formatVersion,
            decoder: decoder,
            failures: .init(
                notFound: GateError.baselineNotFound(path: path),
                unreadable: GateError.unreadableBaseline(path: path),
                unsupported: { GateError.unsupportedBaselineVersion(path: path, version: $0) }
            )
        )
    }

    func write(_ baseline: Baseline, to path: String) throws {
        try VersionedJSON.encode(baseline, dates: .iso8601).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
