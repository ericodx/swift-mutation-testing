import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("PlanJournal")
struct PlanJournalTests {
    @Test("Given verdicts recorded, when read back, then each is there by fingerprint and the last one wins")
    func recordAndRead() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("p/j.jsonl").path
        let mutants = [
            makeMutantDescriptor(id: "m0", utf8Offset: 1, fingerprint: "f0"),
            makeMutantDescriptor(id: "m1", utf8Offset: 2, fingerprint: "f1"),
        ]
        let journal = PlanJournal(path: path, mutants: mutants)

        journal.record(
            status: .survived, for: MutantCacheKey.make(for: mutants[0]), killerTestFile: nil, activated: true,
            duration: 1.5
        )
        journal.record(
            status: .timeout, for: MutantCacheKey.make(for: mutants[1]), killerTestFile: nil, activated: false,
            duration: 30
        )
        journal.record(
            status: .killed(by: "T.t"), for: MutantCacheKey.make(for: mutants[0]), killerTestFile: "Tests/T.swift",
            activated: true, duration: 2
        )

        let entries = PlanJournal.entries(at: path)
        #expect(entries.count == 2)
        #expect(
            entries["f0"]
                == .init(
                    fingerprint: "f0", status: .killed(by: "T.t"), killerTestFile: "Tests/T.swift", activated: true,
                    duration: 2))
        #expect(entries["f1"]?.status == .timeout)
    }

    @Test("Given a key of no mutant of the journal, when recorded, then nothing is written")
    func anUnknownKeyIsIgnored() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("j.jsonl").path
        let journal = PlanJournal(path: path, mutants: [makeMutantDescriptor(id: "m0", fingerprint: "f0")])

        journal.record(
            status: .survived, for: makeMutantCacheKey(utf8Offset: 99), killerTestFile: nil, activated: nil,
            duration: 0
        )

        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("Given a journal whose last line was cut short, when read, then the whole lines are kept")
    func aTruncatedLineIsSkipped() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("j.jsonl").path
        let mutant = makeMutantDescriptor(id: "m0", fingerprint: "f0")
        PlanJournal(path: path, mutants: [mutant]).record(
            status: .survived, for: MutantCacheKey.make(for: mutant), killerTestFile: nil, activated: true,
            duration: 0
        )
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"fingerprint\":\"f1\",\"sta".utf8))
        try handle.close()

        #expect(Array(PlanJournal.entries(at: path).keys) == ["f0"])
    }

    @Test(
        "Given a plan and a shard, when the path is asked, then each shard has its own journal in the cache directory")
    func pathsArePerShard() {
        let whole = PlanJournal.path(projectPath: "/p", planSha256: "abc", shard: nil)
        let shard = PlanJournal.path(projectPath: "/p", planSha256: "abc", shard: Shard(index: 2, count: 4))

        #expect(whole == "/p/.swift-mutation-testing-cache/plans/abc.jsonl")
        #expect(shard == "/p/.swift-mutation-testing-cache/plans/abc-2-of-4.jsonl")
    }

    @Test("Given a cache store with a plan journal and noCache, when a verdict is stored, then the journal has it")
    func theCacheStoreFeedsTheJournalEvenWithoutCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("j.jsonl").path
        let mutant = makeMutantDescriptor(id: "m0", fingerprint: "f0")
        let store = CacheStore(
            storePath: dir.appendingPathComponent("results.json").path, noCache: true,
            planJournal: PlanJournal(path: path, mutants: [mutant])
        )

        await store.store(status: .timeout, for: MutantCacheKey.make(for: mutant), duration: 30)

        #expect(PlanJournal.entries(at: path)["f0"]?.status == .timeout)
        #expect(await store.result(for: MutantCacheKey.make(for: mutant)) == nil)
    }

    @Test("Given a journal that cannot be written, when verdicts are recorded, then one warning names the file")
    func anUnwritableJournalWarnsOnce() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("", named: "blocker", in: dir)
        let path = dir.appendingPathComponent("blocker/j.jsonl").path
        let mutants = [
            makeMutantDescriptor(id: "m0", utf8Offset: 1, fingerprint: "f0"),
            makeMutantDescriptor(id: "m1", utf8Offset: 2, fingerprint: "f1"),
        ]
        let written = Mutex<[String]>([])
        let journal = PlanJournal(
            path: path, mutants: mutants, warning: OnceWarning { line in written.withLock { $0.append(line) } }
        )

        for mutant in mutants {
            journal.record(
                status: .survived, for: MutantCacheKey.make(for: mutant), killerTestFile: nil, activated: true,
                duration: 1
            )
        }

        let warnings = written.withLock { $0 }
        #expect(warnings.count == 1)
        #expect(warnings.first?.hasPrefix("Warning: could not write to '\(path)'") == true)
    }
}
