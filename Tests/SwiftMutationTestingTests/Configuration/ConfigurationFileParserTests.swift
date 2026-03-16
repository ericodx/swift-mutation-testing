import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationFileParser")
struct ConfigurationFileParserTests {
    private let parser = ConfigurationFileParser()

    @Test("returns empty map when file does not exist")
    func returnsEmptyWhenFileAbsent() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = try parser.parse(at: dir.path)

        #expect(result.isEmpty)
    }

    @Test("parses scalar key-value pairs")
    func parsesKeyValuePairs() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "scheme: MyApp\ndestination: platform=macOS\ntimeout: 90\nconcurrency: 3\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result["scheme"] == "MyApp")
        #expect(result["destination"] == "platform=macOS")
        #expect(result["timeout"] == "90")
        #expect(result["concurrency"] == "3")
    }

    @Test("strips double quotes from values")
    func stripsDoubleQuotes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "destination: \"platform=iOS Simulator,name=iPhone 15\"\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result["destination"] == "platform=iOS Simulator,name=iPhone 15")
    }

    @Test("strips single quotes from values")
    func stripsSingleQuotes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "scheme: 'MyApp'\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result["scheme"] == "MyApp")
    }

    @Test("skips comment lines")
    func skipsCommentLines() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "# this is a comment\nscheme: MyApp\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result.count == 1)
        #expect(result["scheme"] == "MyApp")
    }

    @Test("skips empty lines")
    func skipsEmptyLines() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "\nscheme: MyApp\n\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result.count == 1)
    }
}
