import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantLogWriter")
struct MutantLogWriterTests {

    @Test("Given no directory, when constructed, then there is no writer")
    func returnsNilWithoutADirectory() {
        #expect(MutantLogWriter(directory: nil) == nil)
    }

    @Test("Given output, when written, then the file is named after the mutant")
    func writesOneFilePerMutant() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let logs = dir.appendingPathComponent("logs")
        let writer = try #require(MutantLogWriter(directory: logs.path))

        writer.write(
            mutant: makeMutantDescriptor(id: "swift-mutation-testing_7"),
            status: .survived,
            duration: 1.5,
            output: "Test Suite 'All tests' passed"
        )

        let file = logs.appendingPathComponent("swift-mutation-testing_7.log")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Given a verdict, when written, then the header identifies the mutant and the result")
    func headerCarriesTheMutantAndVerdict() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let writer = try #require(MutantLogWriter(directory: dir.path))

        writer.write(
            mutant: makeMutantDescriptor(
                id: "m0",
                filePath: "/work/Sources/Validator.swift",
                line: 18,
                column: 9,
                originalText: ">",
                mutatedText: ">=",
                operatorIdentifier: "RelationalOperatorReplacement"
            ),
            status: .killedByCrash,
            duration: 2.25,
            output: "Fatal error: unexpectedly found nil"
        )

        let contents = try String(contentsOf: dir.appendingPathComponent("m0.log"), encoding: .utf8)

        #expect(contents.contains("/work/Sources/Validator.swift:18:9"))
        #expect(contents.contains("RelationalOperatorReplacement"))
        #expect(contents.contains("> → >="))
        #expect(contents.contains("Crash"))
        #expect(contents.contains("2.25s"))
        #expect(contents.contains("Fatal error: unexpectedly found nil"))
    }

    @Test("Given a killed mutant, when written, then the header names the test that killed it")
    func headerNamesTheKillingTest() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let writer = try #require(MutantLogWriter(directory: dir.path))

        writer.write(
            mutant: makeMutantDescriptor(id: "m1"),
            status: .killed(by: "ValidatorTests.testBoundary"),
            duration: 0.5,
            output: ""
        )

        let contents = try String(contentsOf: dir.appendingPathComponent("m1.log"), encoding: .utf8)

        #expect(contents.contains("Killed by ValidatorTests.testBoundary"))
    }

    @Test("Given an unwritable directory, when written, then the run is not disturbed")
    func silentlySkipsWhenItCannotWrite() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        // A file where the directory should be: creating it fails, and so does the write.
        let blocked = dir.appendingPathComponent("blocked")
        try "not a directory".write(to: blocked, atomically: true, encoding: .utf8)

        let writer = try #require(MutantLogWriter(directory: blocked.path))

        writer.write(mutant: makeMutantDescriptor(), status: .survived, duration: 0, output: "output")
    }
}
