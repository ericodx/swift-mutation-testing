import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("CacheStore")
struct CacheStoreTests {
    @Test("Given stored status, when result queried for same key, then stored status is returned")
    func storeAndResultReturnStoredStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeKey(utf8Offset: 0)

        await store.store(status: .survived, for: key)

        #expect(await store.result(for: key) == .survived)
    }

    @Test("Given unknown key, when result queried, then nil is returned")
    func resultReturnsNilForUnknownKey() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)

        #expect(await store.result(for: makeKey(utf8Offset: 0)) == nil)
    }

    @Test("Given entries stored and persisted, when new store loads same path, then same entries are returned")
    func persistAndLoadRoundtrip() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path
        let key = makeKey(utf8Offset: 5)

        let first = CacheStore(storePath: storePath)
        await first.store(status: .killed(by: "Suite.test"), for: key)
        try await first.persist()

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.result(for: key) == .killed(by: "Suite.test"))
    }

    @Test("Given no cache file exists, when load called, then store remains empty")
    func loadOnMissingFileSucceedsWithEmptyStore() async throws {
        let store = CacheStore(storePath: "/tmp/xmr-nonexistent-\(UUID().uuidString).json")

        try await store.load()

        #expect(await store.result(for: makeKey(utf8Offset: 0)) == nil)
    }

    private func makeKey(utf8Offset: Int) -> MutantCacheKey {
        MutantCacheKey(
            fileContentHash: "abc",
            testFilesHash: "def",
            operatorIdentifier: "binaryOperator",
            utf8Offset: utf8Offset,
            originalText: "a + b",
            mutatedText: "a - b"
        )
    }
}
