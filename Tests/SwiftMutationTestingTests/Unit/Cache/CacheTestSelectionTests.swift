import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("CacheTestSelection")
struct CacheTestSelectionTests {
    @Test("Given an Xcode configuration, when the selection is made, then it names everything the tests ran against")
    func xcodeSelectionNamesSchemeDestinationContainerAndTarget() {
        var build = makeRunnerConfiguration(
            projectType: .xcode(scheme: "App", destination: "platform=iOS Simulator,name=iPhone 17"),
            testTarget: "AppTests"
        ).build
        build.xcodeContainer = .workspace("App.xcworkspace")

        let selection = CacheTestSelection(build)

        #expect(selection.scheme == "App")
        #expect(selection.destination == "platform=iOS Simulator,name=iPhone 17")
        #expect(selection.container == "App.xcworkspace")
        #expect(selection.testTarget == "AppTests")
        #expect(selection.testingFramework == "swift-testing")
    }

    @Test("Given a package, when the selection is made, then it has no scheme or destination")
    func packageSelectionHasTargetAndLibraryOnly() {
        var build = makeRunnerConfiguration(projectType: .spm, testTarget: "UnitTests").build
        build.testingFramework = .xctest

        let selection = CacheTestSelection(build)

        #expect(selection.scheme == nil)
        #expect(selection.destination == nil)
        #expect(selection.testTarget == "UnitTests")
        #expect(selection.testingFramework == "xctest")
    }

    @Test("Given a cache made against another target, when checked, then every verdict is forgotten")
    func anotherTargetDiscardsTheCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (store, key) = try await cache(in: dir, madeWith: selection(target: "UnitTests"))

        let discarded = try await store.discard(unlessMadeWith: selection(target: "EndToEndTests"))

        #expect(discarded)
        #expect(await store.result(for: key) == nil)
        #expect(await store.activated(for: key) == nil)
    }

    @Test("Given a cache made against the same tests, when checked, then its verdicts are kept")
    func theSameSelectionKeepsTheCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (store, key) = try await cache(in: dir, madeWith: selection(target: "UnitTests"))

        let discarded = try await store.discard(unlessMadeWith: selection(target: "UnitTests"))

        #expect(!discarded)
        #expect(await store.result(for: key) == .killed(by: "t"))
    }

    @Test("Given a cache whose metadata names no selection, when checked, then it is discarded")
    func aCacheFromBeforeTheSelectionIsDiscarded() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (store, key) = try await cache(in: dir, madeWith: nil)

        #expect(try await store.discard(unlessMadeWith: selection(target: nil)))
        #expect(await store.result(for: key) == nil)
    }

    @Test("Given verdicts but no metadata to compare with, when checked, then nothing is discarded")
    func verdictsWithoutMetadataAreKept() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let key = MutantCacheKey.make(for: makeMutantDescriptor())
        let store = CacheStore(storePath: dir.appendingPathComponent("results.json").path)
        await store.store(status: .killed(by: "t"), for: key)

        #expect(try await !store.discard(unlessMadeWith: selection(target: "Other")))
        #expect(await store.result(for: key) == .killed(by: "t"))
    }

    @Test("Given xcodebuild arguments, when the selection is made, then it records them")
    func xcodeSelectionRecordsTheArguments() {
        let build = makeRunnerConfiguration(xcodebuildArguments: ["-allowProvisioningUpdates"]).build

        #expect(CacheTestSelection(build).xcodebuildArguments == ["-allowProvisioningUpdates"])
    }

    @Test("Given no xcodebuild argument, when the selection is encoded, then it has no key for them")
    func noArgumentsLeaveTheKeyOut() throws {
        let data = try JSONEncoder().encode(CacheTestSelection(makeRunnerConfiguration().build))

        #expect(!String(decoding: data, as: UTF8.self).contains("xcodebuildArguments"))
    }

    @Test("Given a cache made against other xcodebuild arguments, when checked, then every verdict is forgotten")
    func otherArgumentsDiscardTheCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (store, key) = try await cache(in: dir, madeWith: xcodeSelection([]))

        let discarded = try await store.discard(unlessMadeWith: xcodeSelection(["OTHER_SWIFT_FLAGS=-DMUTATING"]))

        #expect(discarded)
        #expect(await store.result(for: key) == nil)
    }

    @Test("Given a selection written before xcodebuild arguments were recorded, when read, then it matches none")
    func aSelectionWithoutTheKeyMatchesNoArguments() throws {
        let json = #"{"destination":"platform=macOS","scheme":"MyScheme","testingFramework":"swift-testing"}"#

        let decoded = try JSONDecoder().decode(CacheTestSelection.self, from: Data(json.utf8))

        #expect(decoded == CacheTestSelection(makeRunnerConfiguration().build))
    }

    // MARK: - Helpers

    private func selection(target: String?) -> CacheTestSelection {
        CacheTestSelection(makeRunnerConfiguration(projectType: .spm, testTarget: target).build)
    }

    private func xcodeSelection(_ arguments: [String]) -> CacheTestSelection {
        CacheTestSelection(makeRunnerConfiguration(xcodebuildArguments: arguments).build)
    }

    private func cache(
        in dir: URL,
        madeWith selection: CacheTestSelection?
    ) async throws -> (CacheStore, MutantCacheKey) {
        let path = dir.appendingPathComponent("results.json").path
        let key = MutantCacheKey.make(for: makeMutantDescriptor())

        let writer = CacheStore(storePath: path)
        await writer.store(status: .killed(by: "t"), for: key, activated: true)
        try await writer.persist()
        try await writer.persistMetadata(CacheStore.CacheMetadata(testFileHashes: [:], testSelection: selection))

        let reader = CacheStore(storePath: path)
        try await reader.load()
        return (reader, key)
    }
}
