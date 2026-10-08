import CryptoKit
import Foundation

enum VersionedJSON {
    struct Failures {
        let notFound: any Error
        let unreadable: any Error
        let unsupported: (Int) -> any Error
    }

    static func read<Document: Decodable>(
        _: Document.Type,
        from path: String,
        version: Int,
        decoder: JSONDecoder = JSONDecoder(),
        failures: Failures
    ) throws -> Document {
        guard FileManager.default.fileExists(atPath: path) else { throw failures.notFound }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw failures.unreadable }
        guard header.formatVersion == version else { throw failures.unsupported(header.formatVersion) }
        guard let document = try? decoder.decode(Document.self, from: data) else { throw failures.unreadable }

        return document
    }

    static func encode(
        _ document: some Encodable, dates: JSONEncoder.DateEncodingStrategy = .deferredToDate
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = dates
        return try encoder.encode(document) + Data("\n".utf8)
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private struct Header: Decodable {
        let formatVersion: Int
    }
}
