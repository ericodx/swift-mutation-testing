import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("CacheStore — robustness")
struct CacheStoreRobustnessTests {
    @Test("Given a cache journal that cannot be written, when verdicts are stored, then one warning names the file")
    func anUnwritableJournalWarnsOnce() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("", named: "blocker", in: dir)
        let storePath = dir.appendingPathComponent("blocker/cache/results.json").path
        let written = Mutex<[String]>([])
        let store = CacheStore(
            storePath: storePath, journalWarning: OnceWarning { line in written.withLock { $0.append(line) } }
        )

        await store.store(status: .survived, for: makeMutantCacheKey(utf8Offset: 1))
        await store.store(status: .killed(by: "t"), for: makeMutantCacheKey(utf8Offset: 2))

        let warnings = written.withLock { $0 }
        #expect(warnings.count == 1)
        #expect(warnings.first?.contains(CacheStore.journalName) == true)
        #expect(await store.result(for: makeMutantCacheKey(utf8Offset: 1)) == .survived)
    }

    @Test("Given activations in memory and a cache it cannot read, when loaded, then the activations are forgotten too")
    func anUnreadableCacheForgetsTheActivations() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let store = CacheStore(storePath: storePath)
        let key = makeMutantCacheKey()
        await store.store(status: .killed(by: "t"), for: key, killerTestFile: "Tests/T.swift", activated: true)
        try "not json".write(toFile: storePath, atomically: true, encoding: .utf8)

        try await StandardError.$capture.withValue(StandardOutput.Capture()) {
            try await store.load()
        }

        #expect(await store.result(for: key) == nil)
        #expect(await store.killerTestFile(for: key) == nil)
        #expect(await store.activated(for: key) == nil)
    }
}
