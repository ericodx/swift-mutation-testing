import Foundation

struct FileHelpers {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ content: String, named fileName: String, in directory: URL) throws {
        try content.write(
            to: directory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
