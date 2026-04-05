import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationFileParser")
struct ConfigurationFileParserTests {
    private let parser = ConfigurationFileParser()

    @Test("Given no config file present, when parsed, then returns empty map")
    func returnsEmptyWhenFileAbsent() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = try parser.parse(at: dir.path)

        #expect(result.isEmpty)
    }

    @Test("Given a config file with scalar key-value pairs, when parsed, then all pairs are returned")
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

    @Test("Given a config file with double-quoted values, when parsed, then quotes are stripped")
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

    @Test("Given a config file with single-quoted values, when parsed, then quotes are stripped")
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

    @Test("Given a config file with comment lines, when parsed, then comments are ignored")
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

    @Test("Given a config file with empty lines, when parsed, then empty lines are ignored")
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

    @Test("Given a config file with YAML list items, when parsed, then items are joined with comma")
    func parsesYamlListItems() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "exclude-patterns:\n  - /Generated/\n  - /Pods/\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result["exclude-patterns"] == "/Generated/,/Pods/")
    }

    @Test("Given mutators block with all active true, when parsed, then disabledMutators is absent")
    func parsesAllActiveMutators() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yaml = """
            mutators:
              - name: NegateConditional
                active: true
              - name: RemoveSideEffects
                active: true
            """
        try FileHelpers.write(yaml, named: ".swift-mutation-testing.yml", in: dir)

        let result = try parser.parse(at: dir.path)

        #expect(result["disabled-mutators"] == nil)
    }

    @Test("Given mutators block with some active false, when parsed, then disabledMutators lists them")
    func parsesDisabledMutators() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yaml = """
            mutators:
              - name: NegateConditional
                active: true
              - name: RemoveSideEffects
                active: false
              - name: SwapTernary
                active: false
            """
        try FileHelpers.write(yaml, named: ".swift-mutation-testing.yml", in: dir)

        let result = try parser.parse(at: dir.path)

        #expect(result["disabled-mutators"] == "RemoveSideEffects,SwapTernary")
    }

    @Test("Given a config file with sourcesPath key, when parsed, then value is returned")
    func parsesSourcesPath() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try FileHelpers.write(
            "sources-path: /my/sources\n",
            named: ".swift-mutation-testing.yml",
            in: dir
        )

        let result = try parser.parse(at: dir.path)

        #expect(result["sources-path"] == "/my/sources")
    }
}
