import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("CacheStore")
struct CacheStoreTests {
    @Test("Given stored status, when result queried for same key, then stored status is returned")
    func storeAndResultReturnStoredStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 0)

        await store.store(status: .survived, for: key)

        #expect(await store.result(for: key) == .survived)
    }

    @Test("Given unknown key, when result queried, then nil is returned")
    func resultReturnsNilForUnknownKey() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)

        #expect(await store.result(for: makeMutantCacheKey(utf8Offset: 0)) == nil)
    }

    @Test("Given entries stored and persisted, when new store loads same path, then same entries are returned")
    func persistAndLoadRoundtrip() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path
        let key = makeMutantCacheKey(utf8Offset: 5)

        let first = CacheStore(storePath: storePath)
        await first.store(status: .killed(by: "Suite.test"), for: key)
        try await first.persist()

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.result(for: key) == .killed(by: "Suite.test"))
    }

    @Test("Given a verdict stored but not persisted, when another store loads the path, then the verdict is there")
    func aStoredVerdictSurvivesWithoutPersist() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let key = makeMutantCacheKey(utf8Offset: 7)

        let interrupted = CacheStore(storePath: storePath)
        await interrupted.store(
            status: .killed(by: "Suite.test"), for: key, killerTestFile: "Tests/A.swift", activated: true
        )

        let resumed = CacheStore(storePath: storePath)
        try await resumed.load()

        #expect(await resumed.result(for: key) == .killed(by: "Suite.test"))
        #expect(await resumed.killerTestFile(for: key) == "Tests/A.swift")
        #expect(await resumed.activated(for: key) == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(CacheStore.journalName).path))
    }

    @Test("Given persisted results and a journal, when loaded, then the journal's verdicts win")
    func theJournalIsReplayedOverTheResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let key = makeMutantCacheKey(utf8Offset: 7)

        let earlier = CacheStore(storePath: storePath)
        await earlier.store(status: .survived, for: key)
        try await earlier.persist()

        let interrupted = CacheStore(storePath: storePath)
        try await interrupted.load()
        await interrupted.store(status: .killed(by: "Suite.later"), for: key)

        let resumed = CacheStore(storePath: storePath)
        try await resumed.load()

        #expect(await resumed.result(for: key) == .killed(by: "Suite.later"))
    }

    @Test("Given a journal, when the store persists, then the journal is folded into the results and removed")
    func persistFoldsTheJournal() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let journalPath = dir.appendingPathComponent(CacheStore.journalName).path
        let key = makeMutantCacheKey(utf8Offset: 7)

        let store = CacheStore(storePath: storePath)
        await store.store(status: .survived, for: key)
        #expect(FileManager.default.fileExists(atPath: journalPath))

        try await store.persist()

        #expect(!FileManager.default.fileExists(atPath: journalPath))
        let reloaded = CacheStore(storePath: storePath)
        try await reloaded.load()
        #expect(await reloaded.result(for: key) == .survived)
    }

    @Test("Given a journal whose last line was cut short, when loaded, then the whole lines are kept")
    func aTruncatedJournalLineIsSkipped() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let journalPath = dir.appendingPathComponent(CacheStore.journalName).path
        let key = makeMutantCacheKey(utf8Offset: 7)

        let store = CacheStore(storePath: storePath)
        await store.store(status: .survived, for: key)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: journalPath))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"key\":{\"filePath\":\"/tmp/B.sw".utf8))
        try handle.close()

        let resumed = CacheStore(storePath: storePath)
        try await resumed.load()

        #expect(await resumed.result(for: key) == .survived)
    }

    @Test("Given noCache, when a verdict is stored, then no journal is written")
    func noCacheWritesNoJournal() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path, noCache: true)
        await store.store(status: .survived, for: makeMutantCacheKey(utf8Offset: 7))

        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(CacheStore.journalName).path))
    }

    @Test("Given no cache file exists, when load called, then store remains empty")
    func loadOnMissingFileSucceedsWithEmptyStore() async throws {
        let store = CacheStore(storePath: "/tmp/xmr-nonexistent-\(UUID().uuidString).json")

        try await store.load()

        #expect(await store.result(for: makeMutantCacheKey(utf8Offset: 0)) == nil)
    }

    @Test("Given entry with killerTestFile persisted, when loaded, then killerTestFile is preserved")
    func persistAndLoadRoundtripWithKillerTestFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path
        let key = makeMutantCacheKey(utf8Offset: 10)

        let first = CacheStore(storePath: storePath)
        await first.store(status: .killed(by: "Suite.test"), for: key, killerTestFile: "Tests/SuiteTests.swift")
        try await first.persist()

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.result(for: key) == .killed(by: "Suite.test"))
        #expect(await second.killerTestFile(for: key) == "Tests/SuiteTests.swift")
    }

    @Test("Given entry without killerTestFile, when loaded, then killerTestFile is nil")
    func killerTestFileIsNilWhenNotStored() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path
        let key = makeMutantCacheKey(utf8Offset: 11)

        let store = CacheStore(storePath: storePath)
        await store.store(status: .killed(by: "Suite.test"), for: key)
        try await store.persist()

        let loaded = CacheStore(storePath: storePath)
        try await loaded.load()

        #expect(await loaded.result(for: key) == .killed(by: "Suite.test"))
        #expect(await loaded.killerTestFile(for: key) == nil)
    }

    @Test("Given stored metadata, when changedTestFiles called with same hashes, then no changes reported")
    func changedTestFilesReportsNoChangesWhenUnchanged() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let hashes = ["Tests/FooTests.swift": "aaa", "Tests/BarTests.swift": "bbb"]
        try await store.persistMetadata(CacheStore.CacheMetadata(testFileHashes: hashes))

        let diff = try await store.changedTestFiles(current: hashes)

        #expect(!diff.hasChanges)
        #expect(diff.added.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.removed.isEmpty)
    }

    @Test("Given stored metadata, when changedTestFiles called with new file, then added set contains it")
    func changedTestFilesClassifiesAddedFiles() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let stored = ["Tests/FooTests.swift": "aaa"]
        try await store.persistMetadata(CacheStore.CacheMetadata(testFileHashes: stored))

        let current = ["Tests/FooTests.swift": "aaa", "Tests/NewTests.swift": "ccc"]
        let diff = try await store.changedTestFiles(current: current)

        #expect(diff.added == ["Tests/NewTests.swift"])
        #expect(diff.modified.isEmpty)
        #expect(diff.removed.isEmpty)
    }

    @Test("Given stored metadata, when changedTestFiles called with different hash, then modified set contains it")
    func changedTestFilesClassifiesModifiedFiles() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let stored = ["Tests/FooTests.swift": "aaa"]
        try await store.persistMetadata(CacheStore.CacheMetadata(testFileHashes: stored))

        let current = ["Tests/FooTests.swift": "zzz"]
        let diff = try await store.changedTestFiles(current: current)

        #expect(diff.added.isEmpty)
        #expect(diff.modified == ["Tests/FooTests.swift"])
        #expect(diff.removed.isEmpty)
    }

    @Test("Given stored metadata, when changedTestFiles called without a file, then removed set contains it")
    func changedTestFilesClassifiesRemovedFiles() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let stored = ["Tests/FooTests.swift": "aaa", "Tests/OldTests.swift": "bbb"]
        try await store.persistMetadata(CacheStore.CacheMetadata(testFileHashes: stored))

        let current = ["Tests/FooTests.swift": "aaa"]
        let diff = try await store.changedTestFiles(current: current)

        #expect(diff.added.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.removed == ["Tests/OldTests.swift"])
    }

    @Test("Given no metadata exists, when changedTestFiles called, then all files reported as added")
    func changedTestFilesTreatsAllAsAddedWhenNoMetadata() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let current = ["Tests/FooTests.swift": "aaa"]

        let diff = try await store.changedTestFiles(current: current)

        #expect(diff.added == ["Tests/FooTests.swift"])
        #expect(diff.modified.isEmpty)
        #expect(diff.removed.isEmpty)
    }

    @Test("Given metadata persisted and loaded, when round-tripped, then hashes match")
    func metadataPersistAndLoadRoundtrip() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let hashes = ["Tests/A.swift": "abc", "Tests/B.swift": "def"]
        try await store.persistMetadata(CacheStore.CacheMetadata(testFileHashes: hashes))

        let loaded = try await store.loadMetadata()

        #expect(loaded?.testFileHashes == hashes)
    }

    @Test("Given killed entry with unchanged killer file, when invalidated, then entry is kept")
    func invalidateKeepsKilledByUnchangedFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 20)
        await store.store(status: .killed(by: "FooTests.test"), for: key, killerTestFile: "Tests/FooTests.swift")

        let diff = TestFileDiff(added: [], modified: ["Tests/BarTests.swift"], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == .killed(by: "FooTests.test"))
    }

    @Test("Given killed entry with modified killer file, when invalidated, then entry is removed")
    func invalidateRemovesKilledByModifiedFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 21)
        await store.store(status: .killed(by: "FooTests.test"), for: key, killerTestFile: "Tests/FooTests.swift")

        let diff = TestFileDiff(added: [], modified: ["Tests/FooTests.swift"], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given a killed entry whose killer file is edited, when the run repeats, then the verdict is dropped")
    func invalidateDropsKilledVerdictWhenItsKillerTestIsEdited() async throws {
        let project = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(project) }

        let testsDir = project.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let testFile = testsDir.appendingPathComponent("FooTests.swift")
        try "final class FooTests { func testBar() {} }".write(to: testFile, atomically: true, encoding: .utf8)

        let hasher = TestFilesHasher()
        let resolver = KillerTestFileResolver(
            testFilePaths: hasher.testFilePaths(projectPath: project.path),
            projectPath: project.path
        )
        let store = CacheStore(storePath: project.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 42)

        await store.store(
            status: .killed(by: "FooTests.testBar"),
            for: key,
            killerTestFile: resolver.resolve(testName: "FooTests.testBar")
        )
        try await store.persistMetadata(
            CacheStore.CacheMetadata(testFileHashes: hasher.hashPerFile(projectPath: project.path))
        )

        try "final class FooTests {}".write(to: testFile, atomically: true, encoding: .utf8)

        let diff = try await store.changedTestFiles(current: hasher.hashPerFile(projectPath: project.path))
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given killed entry with nil killer file, when invalidated, then entry is removed conservatively")
    func invalidateRemovesKilledWithNilKillerFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 22)
        await store.store(status: .killed(by: "UnknownTest"), for: key)

        let diff = TestFileDiff(added: ["Tests/NewTests.swift"], modified: [], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given a crash verdict, when test files change, then it is re-measured")
    func invalidateRemovesCrashVerdicts() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 90)
        await store.store(status: .killedByCrash, for: key)

        await store.invalidate(diff: TestFileDiff(added: [], modified: ["Tests/FooTests.swift"], removed: []))

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given an unviable entry, when test files change, then it is kept")
    func invalidateKeepsUnviableVerdicts() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 91)
        await store.store(status: .unviable, for: key)

        await store.invalidate(diff: TestFileDiff(added: [], modified: ["Tests/FooTests.swift"], removed: []))

        #expect(await store.result(for: key) == .unviable)
    }

    @Test("Given survived entry, when diff has changes, then entry is removed")
    func invalidateRemovesSurvivedWhenDiffHasChanges() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 23)
        await store.store(status: .survived, for: key)

        let diff = TestFileDiff(added: ["Tests/NewTests.swift"], modified: [], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given survived entry, when no changes, then entry is kept")
    func invalidateKeepsSurvivedWhenNoChanges() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 24)
        await store.store(status: .survived, for: key)

        let diff = TestFileDiff(added: [], modified: [], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == .survived)
    }

    @Test("Given unviable entry, when invalidated, then entry is always kept")
    func invalidateAlwaysKeepsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 25)
        await store.store(status: .unviable, for: key)

        let diff = TestFileDiff(
            added: ["Tests/New.swift"], modified: ["Tests/Old.swift"], removed: ["Tests/Gone.swift"])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == .unviable)
    }

    @Test("Given noCoverage entry, when diff has changes, then entry is removed")
    func invalidateRemovesNoCoverageWhenDiffHasChanges() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 27)
        await store.store(status: .noCoverage, for: key)

        let diff = TestFileDiff(added: ["Tests/New.swift"], modified: [], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given timeout entry, when diff has changes, then entry is removed")
    func invalidateRemovesTimeoutWhenDiffHasChanges() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 28)
        await store.store(status: .timeout, for: key)

        let diff = TestFileDiff(added: [], modified: ["Tests/Changed.swift"], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given killed entry with removed killer file, when invalidated, then entry is removed")
    func invalidateRemovesKilledByRemovedFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey(utf8Offset: 29)
        await store.store(status: .killed(by: "OldTests.test"), for: key, killerTestFile: "Tests/OldTests.swift")

        let diff = TestFileDiff(added: [], modified: [], removed: ["Tests/OldTests.swift"])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: key) == nil)
    }

    @Test("Given renamed test file, when invalidated, then killed pointing to old path removed and survived removed")
    func invalidateHandlesRenamedTestFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let killedKey = makeMutantCacheKey(utf8Offset: 30)
        let survivedKey = makeMutantCacheKey(utf8Offset: 31)
        let unrelatedKilledKey = makeMutantCacheKey(utf8Offset: 32)
        await store.store(
            status: .killed(by: "OldTests.test"), for: killedKey, killerTestFile: "Tests/OldTests.swift")
        await store.store(status: .survived, for: survivedKey)
        await store.store(
            status: .killed(by: "Other.test"), for: unrelatedKilledKey, killerTestFile: "Tests/OtherTests.swift")

        let diff = TestFileDiff(
            added: ["Tests/RenamedTests.swift"],
            modified: [],
            removed: ["Tests/OldTests.swift"]
        )
        await store.invalidate(diff: diff)

        #expect(await store.result(for: killedKey) == nil)
        #expect(await store.result(for: survivedKey) == nil)
        #expect(await store.result(for: unrelatedKilledKey) == .killed(by: "Other.test"))
    }

    @Test(
        "Given old cache format without killerTestFile, when loaded and invalidated, then entries treated conservatively"
    )
    func oldCacheFormatWithoutKillerTestFileTreatedConservatively() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path
        let key = makeMutantCacheKey(utf8Offset: 33)

        let store = CacheStore(storePath: storePath)
        await store.store(status: .killed(by: "SomeTest.test"), for: key)
        try await store.persist()

        let reloaded = CacheStore(storePath: storePath)
        try await reloaded.load()

        #expect(await reloaded.killerTestFile(for: key) == nil)

        let diff = TestFileDiff(added: ["Tests/New.swift"], modified: [], removed: [])
        await reloaded.invalidate(diff: diff)

        #expect(await reloaded.result(for: key) == nil)
    }

    @Test("Given added test file, when invalidated, then killed entries with known files are kept")
    func invalidateKeepsKilledEntriesWhenTestFileAdded() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let killedKey = makeMutantCacheKey(utf8Offset: 34)
        let survivedKey = makeMutantCacheKey(utf8Offset: 35)
        let noCoverageKey = makeMutantCacheKey(utf8Offset: 36)
        await store.store(
            status: .killed(by: "FooTests.test"), for: killedKey, killerTestFile: "Tests/FooTests.swift")
        await store.store(status: .survived, for: survivedKey)
        await store.store(status: .noCoverage, for: noCoverageKey)

        let diff = TestFileDiff(added: ["Tests/NewTests.swift"], modified: [], removed: [])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: killedKey) == .killed(by: "FooTests.test"))
        #expect(await store.result(for: survivedKey) == nil)
        #expect(await store.result(for: noCoverageKey) == nil)
    }

    @Test("Given deleted test file, when invalidated, then killed entries pointing to it are removed")
    func invalidateRemovesKilledEntriesWhenTestFileDeleted() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let affectedKey = makeMutantCacheKey(utf8Offset: 37)
        let unaffectedKey = makeMutantCacheKey(utf8Offset: 38)
        let survivedKey = makeMutantCacheKey(utf8Offset: 39)
        await store.store(
            status: .killed(by: "Gone.test"), for: affectedKey, killerTestFile: "Tests/GoneTests.swift")
        await store.store(
            status: .killed(by: "Still.test"), for: unaffectedKey, killerTestFile: "Tests/StillTests.swift")
        await store.store(status: .survived, for: survivedKey)

        let diff = TestFileDiff(added: [], modified: [], removed: ["Tests/GoneTests.swift"])
        await store.invalidate(diff: diff)

        #expect(await store.result(for: affectedKey) == nil)
        #expect(await store.result(for: unaffectedKey) == .killed(by: "Still.test"))
        #expect(await store.result(for: survivedKey) == nil)
    }

    @Test(
        "Given metadata persisted, when loaded by new store, then changedTestFiles detects no-cache metadata correctly")
    func metadataPersistedAndLoadedForNextRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path

        let first = CacheStore(storePath: storePath)
        let hashes = ["Tests/A.swift": "hash1", "Tests/B.swift": "hash2"]
        try await first.persistMetadata(CacheStore.CacheMetadata(testFileHashes: hashes))

        let second = CacheStore(storePath: storePath)
        let diff = try await second.changedTestFiles(current: hashes)

        #expect(!diff.hasChanges)
    }

    @Test("Given a timeout verdict, when stored, then it is not kept — a timeout says nothing about the mutant")
    func timeoutIsNeverStored() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let store = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let key = makeMutantCacheKey()

        await store.store(status: .timeout, for: key)

        #expect(await store.result(for: key) == nil)
    }

    // MARK: - Unreadable caches

    @Test("Given results written before the key carried the file path, when loaded, then the cache is ignored")
    func loadIgnoresResultsFromBeforeTheKeyCarriedThePath() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let written = """
            [{"key":{"fileContentHash":"abc","operatorIdentifier":"binaryOperator","utf8Offset":0,\
            "originalText":"a + b","mutatedText":"a - b"},"status":{"kind":"survived"}}]
            """
        try written.write(toFile: storePath, atomically: true, encoding: .utf8)

        let store = CacheStore(storePath: storePath)
        try await store.load()

        #expect(await store.result(for: makeMutantCacheKey()) == nil)
    }

    @Test("Given results that are not JSON, when loaded, then the cache is ignored")
    func loadIgnoresResultsThatAreNotJSON() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        try "not valid json".write(toFile: storePath, atomically: true, encoding: .utf8)

        let store = CacheStore(storePath: storePath)
        try await store.load()

        #expect(await store.result(for: makeMutantCacheKey()) == nil)
    }

    @Test("Given metadata without a format version, when loaded, then readable results are ignored too")
    func loadIgnoresResultsWhoseMetadataHasNoFormatVersion() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let first = CacheStore(storePath: storePath)
        await first.store(status: .survived, for: makeMutantCacheKey())
        try await first.persist()
        try #"{"testFileHashes":{"Tests/A.swift":"abc"}}"#.write(
            to: dir.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8
        )

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.result(for: makeMutantCacheKey()) == nil)
        #expect(try await second.loadMetadata() == nil)
    }

    @Test("Given metadata from another format version, when loaded, then readable results are ignored too")
    func loadIgnoresResultsFromAnotherFormatVersion() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let first = CacheStore(storePath: storePath)
        await first.store(status: .survived, for: makeMutantCacheKey())
        try await first.persist()
        try await first.persistMetadata(
            CacheStore.CacheMetadata(testFileHashes: [:], formatVersion: CacheStore.formatVersion + 1)
        )

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.result(for: makeMutantCacheKey()) == nil)
        #expect(try await second.loadMetadata() == nil)
    }

    @Test("Given metadata from this format version, when loaded, then the results are kept")
    func loadKeepsResultsFromThisFormatVersion() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("results.json").path
        let first = CacheStore(storePath: storePath)
        await first.store(status: .survived, for: makeMutantCacheKey())
        try await first.persist()
        try await first.persistMetadata(CacheStore.CacheMetadata(testFileHashes: ["Tests/A.swift": "abc"]))

        let second = CacheStore(storePath: storePath)
        try await second.load()

        #expect(await second.result(for: makeMutantCacheKey()) == .survived)
        #expect(try await second.loadMetadata()?.formatVersion == CacheStore.formatVersion)
    }

    @Test("Given results that cannot be read from disk, when loaded, then the error still propagates")
    func loadStillThrowsWhenResultsCannotBeRead() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storeURL = dir.appendingPathComponent("results.json")
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)

        let store = CacheStore(storePath: storeURL.path)

        await #expect(throws: (any Error).self) {
            try await store.load()
        }
    }

    @Test("Given a verdict stored with its activation, when persisted and reloaded, then the activation is kept")
    func activationRoundTrips() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("results.json").path
        let ran = makeMutantCacheKey(utf8Offset: 1)
        let neverRan = makeMutantCacheKey(utf8Offset: 2)
        let unknown = makeMutantCacheKey(utf8Offset: 3)

        let first = CacheStore(storePath: path)
        await first.store(status: .survived, for: ran, activated: true)
        await first.store(status: .noCoverage, for: neverRan, activated: false)
        await first.store(status: .unviable, for: unknown)
        try await first.persist()

        let second = CacheStore(storePath: path)
        try await second.load()

        #expect(await second.activated(for: ran) == true)
        #expect(await second.activated(for: neverRan) == false)
        #expect(await second.activated(for: unknown) == nil)
        #expect(await second.result(for: neverRan) == .noCoverage)
    }

    @Test("Given an invalidated verdict, when its activation is asked for, then it is gone too")
    func invalidationForgetsTheActivation() async {
        let store = CacheStore(storePath: "/unused/results.json")
        let key = makeMutantCacheKey()
        await store.store(status: .survived, for: key, activated: true)

        await store.invalidate(diff: TestFileDiff(added: ["Tests/New.swift"], modified: [], removed: []))

        #expect(await store.result(for: key) == nil)
        #expect(await store.activated(for: key) == nil)
    }

    @Test("Given incompatible mutants now carry their activation, when checked, then the format version is 3")
    func formatVersionIsThree() {
        #expect(CacheStore.formatVersion == 3)
    }

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
}
