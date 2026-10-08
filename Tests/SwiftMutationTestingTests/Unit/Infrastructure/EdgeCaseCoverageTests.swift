import Foundation
import SwiftIfConfig
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftMutationTesting

@Suite("Edge cases — parser, discovery and processes")
struct EdgeCaseCoverageTests {
    @Test(
        "Given a positional argument too many, when parsed, then it is named",
        arguments: [
            (["/p", "extra"], "extra"),
            (["reproduce", "3f2a9c", "/p", "extra"], "extra"),
        ]
    )
    func aPositionalTooManyIsRefused(arguments: [String], extra: String) {
        #expect {
            try CommandLineParser().parse(arguments)
        } throws: { error in
            (error as? UsageError)?.message == "unexpected argument '\(extra)'"
        }
    }

    @Test("Given a workspace outside the project root, when located, then it is refused")
    func aWorkspaceOutsideTheRootIsRefused() throws {
        let root = try FileHelpers.makeTemporaryDirectory()
        let outside = try FileHelpers.makeTemporaryDirectory()
        defer {
            FileHelpers.cleanup(root)
            FileHelpers.cleanup(outside)
        }
        let workspace = outside.appendingPathComponent("App.xcworkspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        #expect {
            try XcodeContainerLocator.locate(in: root, workspace: workspace.path, project: nil)
        } throws: { error in
            (error as? UsageError)?.message.contains("is outside the project root") == true
        }
    }

    @Test("Given the host configuration, when asked, then it answers as the macOS build the tool runs")
    func theHostConfigurationAnswersForMacOS() throws {
        let host = HostBuildConfiguration()

        #expect(try host.isCustomConditionSet(name: "DEBUG"))
        #expect(try !host.hasFeature(name: "Embedded"))
        #expect(try !host.hasAttribute(name: "objc"))
        #expect(try !host.isActiveTargetEnvironment(name: "simulator"))
        #expect(try host.isActiveTargetRuntime(name: "_ObjC"))
        #expect(try !host.isActiveTargetPointerAuthentication(name: "arm64e"))
        #expect(try host.isActiveTargetObjectFormat(name: "MachO"))
        #expect(host.targetPointerBitWidth == 64)
        #expect(host.targetAtomicBitWidths == [8, 16, 32, 64, 128])
        #expect(host.endianness == .little)
    }

    @Test("Given canImport with no module named, when asked, then the host cannot decide it")
    func canImportOfNothingIsUndecidable() {
        #expect(throws: HostBuildConfiguration.ImportError.self) {
            try HostBuildConfiguration().canImport(importPath: [], version: .unversioned)
        }
    }

    @Test("Given an error outside every #if condition, when mapped, then no declaration can be dropped safely")
    func anErrorOutsideEveryConditionMapsToNothing() throws {
        let syntax = Parser.parse(source: "let a = 1\n#if canImport(Nope)\nlet b = 2\n#endif\n")
        let clauses = syntax.configuredRegions(in: HostBuildConfiguration()).map(\.0)

        let outside = InactiveRegionExtractor.undecidableDeclarations(
            at: [AbsolutePosition(utf8Offset: 0)], among: clauses
        )
        let inside = InactiveRegionExtractor.undecidableDeclarations(
            at: [AbsolutePosition(utf8Offset: 14)], among: clauses
        )

        #expect(outside == nil)
        #expect(inside?.count == 1)
    }

    @Test("Given a mutation in the comment that ends the file, when instrumented, then no expression holds it")
    func aMutationInTheClosingCommentIsLeftUnmeasured() throws {
        let content = "let x = 1\n// a closing note"
        let offset = content.utf8.distance(
            from: content.utf8.startIndex, to: try #require(content.range(of: "note")).lowerBound
        )
        let mutant = makeMutantDescriptor(
            filePath: "/p/A.swift", utf8Offset: offset, mutatedText: "note", mutatedSourceContent: content
        )

        #expect(ActivationInstrumenter(importStyle: .implicit).instrument(mutant) == nil)
    }

    @Test("Given a process group that was never registered, when taken back, then the registry is unchanged")
    func deregisteringAnUnknownGroupChangesNothing() {
        let registry = ProcessGroupRegistry(capacity: 2)
        let killed = KilledGroups()
        registry.register(4242)

        registry.deregister(9999)
        registry.killAll(kill: killed.record)

        #expect(killed.pids == [-4242])
    }

    @Test("Given every slot taken, when another group is registered, then it is not kept")
    func aFullRegistryKeepsNoMoreGroups() {
        let registry = ProcessGroupRegistry(capacity: 1)
        let killed = KilledGroups()

        registry.register(4242)
        registry.register(4343)
        registry.killAll(kill: killed.record)

        #expect(killed.pids == [-4242])
    }

    @Test(
        "Given a process that already ended, when tracked, then its group is taken back at once",
        arguments: [(true, [pid_t(-4242)]), (false, [])]
    )
    func aProcessThatAlreadyEndedIsNotKept(isRunning: Bool, expected: [pid_t]) {
        let registry = ProcessGroupRegistry(capacity: 2)
        let killed = KilledGroups()

        ProcessRunner.track(4242, isRunning: { isRunning }, in: registry)
        registry.killAll(kill: killed.record)

        #expect(killed.pids == expected)
    }

    @Test("Given the process's own signal target, when read, then it points at the shared registries")
    func theProcessSignalTargetUsesTheSharedRegistries() {
        let target = SandboxCleaner.SignalTarget.process

        #expect(target.registry === SandboxRegistry.shared)
        #expect(target.processGroups === ProcessGroupRegistry.shared)
    }
}

private final class KilledGroups: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [pid_t] = []

    var pids: [pid_t] {
        lock.withLock { recorded }
    }

    var record: SystemCalls.Kill {
        { [self] pid, _ in
            lock.withLock { recorded.append(pid) }
            return 0
        }
    }
}
