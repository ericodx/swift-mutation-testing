import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("CacheStore — durations")
struct CacheStoreDurationTests {
    @Test("Given a timeout stored with its duration, when queried, then the duration is known and the verdict is not")
    func aTimeoutKeepsItsDurationButNoVerdict() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path)
        let mutant = makeMutantDescriptor(utf8Offset: 3)

        await store.store(status: .timeout, for: MutantCacheKey.make(for: mutant), duration: 60)

        #expect(await store.cachedResult(for: mutant) == nil)
        #expect(await store.durations(for: [mutant]) == [60])
    }

    @Test("Given verdicts and a timeout persisted, when another store loads the path, then every duration is back")
    func durationsSurvivePersistAndLoad() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let killed = makeMutantDescriptor(utf8Offset: 1)
        let timedOut = makeMutantDescriptor(utf8Offset: 2)
        let unknown = makeMutantDescriptor(utf8Offset: 3)
        let first = CacheStore(storePath: storePath)
        await first.store(status: .killed(by: "Suite.test"), for: MutantCacheKey.make(for: killed), duration: 4.5)
        await first.store(status: .timeout, for: MutantCacheKey.make(for: timedOut), duration: 60)
        try await first.persist()

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.durations(for: [killed, timedOut, unknown]) == [4.5, 60, nil])
        #expect(await second.result(for: MutantCacheKey.make(for: killed)) == .killed(by: "Suite.test"))
        #expect(await second.result(for: MutantCacheKey.make(for: timedOut)) == nil)
    }

    @Test("Given a timeout stored but not persisted, when another store loads the path, then its duration is there")
    func aTimeoutsDurationSurvivesThroughTheJournal() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let mutant = makeMutantDescriptor(utf8Offset: 9)
        let interrupted = CacheStore(storePath: storePath)
        await interrupted.store(status: .timeout, for: MutantCacheKey.make(for: mutant), duration: 31)

        let next = CacheStore(storePath: storePath)
        try await next.load()

        #expect(await next.durations(for: [mutant]) == [31])
        #expect(await next.cachedResult(for: mutant) == nil)
    }

    @Test("Given a killed verdict forgotten because its test changed, when queried, then its duration is kept")
    func invalidationKeepsTheDuration() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path)
        let mutant = makeMutantDescriptor(utf8Offset: 4)
        let key = MutantCacheKey.make(for: mutant)
        await store.store(status: .killed(by: "Suite.test"), for: key, killerTestFile: "Tests/A.swift", duration: 8)

        await store.invalidate(diff: TestFileDiff(added: [], modified: ["Tests/A.swift"], removed: []))

        #expect(await store.result(for: key) == nil)
        #expect(await store.durations(for: [mutant]) == [8])
    }

    @Test("Given a cache made against other tests, when discarded, then the durations go with the verdicts")
    func discardingForAnotherSelectionDropsTheDurations() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path)
        let mutant = makeMutantDescriptor(utf8Offset: 4)
        await store.store(status: .survived, for: MutantCacheKey.make(for: mutant), duration: 8)
        var build = makeRunnerConfiguration(projectType: .spm).build
        build.testTarget = "A"
        try await store.persistMetadata(
            CacheStore.CacheMetadata(testFileHashes: [:], testSelection: CacheTestSelection(build))
        )
        build.testTarget = "B"

        _ = try await store.discard(unlessMadeWith: CacheTestSelection(build))

        #expect(await store.durations(for: [mutant]) == [nil])
    }

    @Test("Given noCache, when a duration is stored and queried, then nothing is known and nothing is written")
    func noCacheKnowsNoDuration() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path, noCache: true)
        let mutant = makeMutantDescriptor(utf8Offset: 4)

        await store.store(status: .timeout, for: MutantCacheKey.make(for: mutant), duration: 60)

        #expect(await store.durations(for: [mutant]) == [nil])
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("journal.jsonl").path))
    }

    @Test("Given a results file from before durations were kept, when loaded, then the verdicts still read")
    func anEntryWithoutDurationStillLoads() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let storePath = dir.appendingPathComponent("results.json").path
        let mutant = makeMutantDescriptor(utf8Offset: 2)
        let key = MutantCacheKey.make(for: mutant)
        struct EntryBeforeDurations: Encodable {
            let key: MutantCacheKey
            let status: ExecutionStatus
            let killerTestFile: String?
            let activated: Bool?
        }
        let entry = EntryBeforeDurations(key: key, status: .survived, killerTestFile: nil, activated: nil)
        try JSONEncoder().encode([entry]).write(to: URL(fileURLWithPath: storePath))

        let store = CacheStore(storePath: storePath)
        try await store.load()

        #expect(await store.result(for: key) == .survived)
        #expect(await store.durations(for: [mutant]) == [nil])
    }
}
