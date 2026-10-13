import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("BaselineStore")
struct BaselineStoreTests {
    private let store = BaselineStore()

    @Test("Given a written baseline, when read back, then it is equal")
    func roundTrips() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("baseline.json").path
        let baseline = makeBaseline(score: 91.25, undetected: ["b", "a"])

        try store.write(baseline, to: path)

        #expect(try store.read(from: path) == baseline)
    }

    @Test("Given a baseline without a score, when read back, then it still has none")
    func roundTripsWithoutAScore() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("baseline.json").path
        let baseline = makeBaseline(score: nil)

        try store.write(baseline, to: path)

        #expect(try store.read(from: path).score == nil)
    }

    @Test("Given the same baseline written twice, when compared, then the files are identical and keys sorted")
    func writesDeterministically() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let first = dir.appendingPathComponent("first.json").path
        let second = dir.appendingPathComponent("second.json").path

        try store.write(makeBaseline(undetected: ["a", "b"]), to: first)
        try store.write(makeBaseline(undetected: ["a", "b"]), to: second)

        let text = try String(contentsOfFile: first, encoding: .utf8)
        #expect(try Data(contentsOf: URL(fileURLWithPath: first)) == Data(contentsOf: URL(fileURLWithPath: second)))
        let createdAt = try #require(text.range(of: "\"createdAt\""))
        let score = try #require(text.range(of: "\"score\""))
        #expect(createdAt.lowerBound < score.lowerBound)
        #expect(text.contains("\"createdAt\" : \"2026-09-21T"))
        #expect(text.hasSuffix("}\n"))
    }

    @Test("Given no file, when read, then the baseline is reported missing")
    func missingFileIsReported() {
        #expect(throws: GateError.baselineNotFound(path: "/nonexistent/baseline.json")) {
            try store.read(from: "/nonexistent/baseline.json")
        }
    }

    @Test("Given a file that is not a baseline, when read, then it is reported unreadable")
    func garbageIsUnreadable() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("baseline.json").path
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: GateError.unreadableBaseline(path: path)) {
            try store.read(from: path)
        }
    }

    @Test("Given the right version but missing fields, when read, then it is reported unreadable")
    func incompleteBaselineIsUnreadable() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("baseline.json").path
        try #"{"formatVersion": 1}"#.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: GateError.unreadableBaseline(path: path)) {
            try store.read(from: path)
        }
    }

    @Test("Given a baseline of an unknown format version, when read, then the version is reported")
    func unknownVersionIsReported() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("baseline.json").path
        try #"{"formatVersion": 99}"#.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: GateError.unsupportedBaselineVersion(path: path, version: 99)) {
            try store.read(from: path)
        }
    }
}
