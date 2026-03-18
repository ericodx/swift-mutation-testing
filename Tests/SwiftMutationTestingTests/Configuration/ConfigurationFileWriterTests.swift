import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationFileWriter")
struct ConfigurationFileWriterTests {
    private let writer = ConfigurationFileWriter()

    @Test("Given empty directory, when write called, then config file is created with all keys commented")
    func createsConfigFileWithCommentedKeys() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path)

        let fileURL = dir.appendingPathComponent(".swift-mutation-testing.yml")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("scheme"))
        #expect(content.contains("destination"))
        #expect(content.contains("timeout"))
        #expect(content.contains("concurrency"))
    }

    @Test("Given existing config file, when write called, then throws UsageError")
    func throwsWhenFileAlreadyExists() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path)

        #expect(throws: UsageError.self) {
            try writer.write(to: dir.path)
        }
    }

    @Test("Given generated config file, when parsed by ConfigurationFileParser, then returns empty map")
    func generatedFileProducesEmptyMapWhenAllCommented() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path)

        let values = try ConfigurationFileParser().parse(at: dir.path)
        #expect(values.isEmpty)
    }
}
