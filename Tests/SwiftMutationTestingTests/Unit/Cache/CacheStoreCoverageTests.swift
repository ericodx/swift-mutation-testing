import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("CacheStore — coverage")
struct CacheStoreCoverageTests {
    private let coverage = TestCoverage(
        sites: ["ab:9": [TestReference(library: .xctest, id: "PkgTests.ATests/testA")]], outside: ["ab:40"]
    )
    private let hashes = ["Sources/A.swift": "h1"]
    private let unchanged = TestFileDiff(added: [], modified: [], removed: [])

    private func metadata(_ sourceHashes: [String: String]?) -> CacheStore.CacheMetadata {
        CacheStore.CacheMetadata(testFileHashes: ["Tests/T.swift": "t1"], sourceHashes: sourceHashes)
    }

    @Test("Given a map stored and persisted, when another store adopts it with the same sources, then it is back")
    func aPersistedMapIsAdoptedWhenNothingChanged() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let first = CacheStore(storePath: storePath)
        await first.storeCoverage(coverage)
        try await first.persistMetadata(metadata(hashes))

        let second = CacheStore(storePath: storePath)
        try await second.adoptCoverage(unless: unchanged, sourceHashes: hashes)

        #expect(await second.coverage == coverage)
    }

    @Test("Given a persisted map, when a test file changed, then it is not adopted")
    func aChangedTestFileDropsTheMap() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let first = CacheStore(storePath: storePath)
        await first.storeCoverage(coverage)
        try await first.persistMetadata(metadata(hashes))

        let second = CacheStore(storePath: storePath)
        try await second.adoptCoverage(
            unless: TestFileDiff(added: [], modified: ["Tests/T.swift"], removed: []), sourceHashes: hashes
        )

        #expect(await second.coverage == nil)
    }

    @Test("Given a persisted map, when a source file changed, then it is not adopted")
    func aChangedSourceFileDropsTheMap() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let first = CacheStore(storePath: storePath)
        await first.storeCoverage(coverage)
        try await first.persistMetadata(metadata(hashes))

        let second = CacheStore(storePath: storePath)
        try await second.adoptCoverage(unless: unchanged, sourceHashes: ["Sources/A.swift": "h2"])

        #expect(await second.coverage == nil)
    }

    @Test("Given noCache, when a map is stored, then the store knows none")
    func noCacheKeepsNoMap() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path, noCache: true)

        await store.storeCoverage(coverage)

        #expect(await store.coverage == nil)
    }

    @Test("Given a metadata file from before coverage was kept, when loaded, then there is no map and no error")
    func metadataWithoutCoverageStillLoads() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let store = CacheStore(storePath: storePath)
        struct MetadataBeforeCoverage: Encodable {
            let formatVersion: Int
            let testFileHashes: [String: String]
        }
        let old = MetadataBeforeCoverage(formatVersion: CacheStore.formatVersion, testFileHashes: [:])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: dir.appendingPathComponent("metadata.json"))

        try await store.adoptCoverage(unless: unchanged, sourceHashes: hashes)

        #expect(await store.coverage == nil)
        #expect(try await store.loadMetadata() != nil)
    }
}
