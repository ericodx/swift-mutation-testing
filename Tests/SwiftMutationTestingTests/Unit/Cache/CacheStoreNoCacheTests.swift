import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("CacheStore with noCache")
struct CacheStoreNoCacheTests {

    @Test("Given noCache, when a verdict is stored and persisted, then nothing is written to disk")
    func doesNotWriteResultsToDisk() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let store = CacheStore(storePath: storePath, noCache: true)

        await store.store(status: .survived, for: makeMutantCacheKey(utf8Offset: 1))
        try await store.persist()

        #expect(!FileManager.default.fileExists(atPath: storePath))
    }

    @Test("Given noCache, when metadata is persisted, then nothing is written to disk")
    func doesNotWriteMetadataToDisk() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let metadataPath = dir.appendingPathComponent("metadata.json").path
        let store = CacheStore(storePath: storePath, noCache: true)

        try await store.persistMetadata(CacheStore.CacheMetadata(testFileHashes: ["Tests/A.swift": "abc"]))

        #expect(!FileManager.default.fileExists(atPath: metadataPath))
    }

    @Test("Given a cache written by an earlier run, when noCache loads it, then no verdict is returned")
    func doesNotReplayVerdictsFromDisk() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let key = makeMutantCacheKey(utf8Offset: 2)

        let firstRun = CacheStore(storePath: storePath)
        await firstRun.store(status: .survived, for: key, killerTestFile: "Tests/FooTests.swift")
        try await firstRun.persist()

        let secondRun = CacheStore(storePath: storePath, noCache: true)
        try await secondRun.load()

        #expect(await secondRun.result(for: key) == nil)
        #expect(await secondRun.killerTestFile(for: key) == nil)
    }

    @Test("Given noCache, when a run finishes, then an existing cache is left untouched")
    func leavesAnExistingCacheIntact() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let key = makeMutantCacheKey(utf8Offset: 3)

        let firstRun = CacheStore(storePath: storePath)
        await firstRun.store(status: .survived, for: key)
        try await firstRun.persist()
        let original = try Data(contentsOf: URL(fileURLWithPath: storePath))

        let secondRun = CacheStore(storePath: storePath, noCache: true)
        try await secondRun.load()
        await secondRun.store(status: .timeout, for: key)
        try await secondRun.persist()

        #expect(try Data(contentsOf: URL(fileURLWithPath: storePath)) == original)
    }

    @Test("Given noCache is false, when a verdict is stored and persisted, then it is written")
    func stillWritesWhenCachingIsEnabled() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let store = CacheStore(storePath: storePath)

        await store.store(status: .survived, for: makeMutantCacheKey(utf8Offset: 4))
        try await store.persist()

        #expect(FileManager.default.fileExists(atPath: storePath))
    }
}
