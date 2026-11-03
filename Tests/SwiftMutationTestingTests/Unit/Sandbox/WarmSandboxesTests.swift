import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("WarmSandboxes")
struct WarmSandboxesTests {

    @Test("Given a project, when a slot is claimed twice without a release, then the second claim takes the next slot")
    func claimsTheNextFreeSlot() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let project = try makeProject(in: dir)
        let warm = WarmSandboxes(directory: dir.appendingPathComponent("sandboxes"))

        let (first, firstSlot) = try warm.claim(projectPath: project.path)
        let (second, secondSlot) = try warm.claim(projectPath: project.path)
        defer {
            firstSlot.unlock()
            secondSlot.unlock()
        }

        #expect(firstSlot.index == 0)
        #expect(secondSlot.index == 1)
        #expect(first.lastPathComponent == WarmSandboxes.name(for: project.path, slot: 0))
        #expect(second.lastPathComponent == WarmSandboxes.name(for: project.path, slot: 1))
        #expect(first.lastPathComponent.hasPrefix(WarmSandboxes.prefix))
        #expect(
            try String(contentsOf: first.appendingPathComponent(WarmSandboxes.lockName), encoding: .utf8)
                == "\(getpid())\n"
        )
    }

    @Test("Given a released slot, when claimed again, then the same slot is taken")
    func aReleasedSlotIsClaimedAgain() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let project = try makeProject(in: dir)
        let warm = WarmSandboxes(directory: dir.appendingPathComponent("sandboxes"))

        let (first, firstSlot) = try warm.claim(projectPath: project.path)
        firstSlot.unlock()
        let (again, againSlot) = try warm.claim(projectPath: project.path)
        defer { againSlot.unlock() }

        #expect(againSlot.index == 0)
        #expect(again.path == first.path)
    }

    @Test("Given a slot held by another process, when claimed, then the next slot is taken")
    func aSlotHeldByAnotherProcessIsSkipped() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let project = try makeProject(in: dir)
        let warm = WarmSandboxes(directory: dir.appendingPathComponent("sandboxes"))
        let (first, firstSlot) = try warm.claim(projectPath: project.path)
        firstSlot.unlock()

        let holder = try Self.holdLock(at: first.appendingPathComponent(WarmSandboxes.lockName))
        defer { holder.terminate() }

        let (second, secondSlot) = try warm.claim(projectPath: project.path)
        defer { secondSlot.unlock() }

        #expect(secondSlot.index == 1)
        #expect(second != first)
    }

    @Test("Given two projects, when named, then their slots differ, and a symlink to a project names the same slot")
    func theNameFollowsTheResolvedProject() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let project = try makeProject(in: dir)
        let other = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(other) }
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)

        #expect(WarmSandboxes.key(for: project.path) == WarmSandboxes.key(for: link.path))
        #expect(WarmSandboxes.key(for: project.path) != WarmSandboxes.key(for: other.path))
        #expect(WarmSandboxes.key(for: project.path).count == 16)
    }

    @Test("Given free and held slots of a project, when removeAll called, then the free ones go and the held one stays")
    func removeAllLeavesAHeldSlot() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let project = try makeProject(in: dir)
        let other = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(other) }
        let warm = WarmSandboxes(directory: dir.appendingPathComponent("sandboxes"))

        let (held, heldSlot) = try warm.claim(projectPath: project.path)
        defer { heldSlot.unlock() }
        let (free, freeSlot) = try warm.claim(projectPath: project.path)
        freeSlot.unlock()
        let (foreign, foreignSlot) = try warm.claim(projectPath: other.path)
        foreignSlot.unlock()

        warm.removeAll(projectPath: project.path)

        #expect(FileManager.default.fileExists(atPath: held.path))
        #expect(!FileManager.default.fileExists(atPath: free.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))
        #expect(warm.slots(of: project.path).map(\.lastPathComponent) == [held.lastPathComponent])
    }

    @Test(
        "Given a sandbox from an earlier run, when pruned, then the build directories, the lock and the kept files stay"
    )
    func pruneKeepsTheBuildAndTheKeptFiles() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sandbox = dir.appendingPathComponent("sandbox")
        for path in [
            ".build/debug/App.o", ".xmr-derived-data/Build/x", "lock", "Sources/App/Kept.swift",
            "Sources/App/Stale.swift", "Sources/Other/Old.swift", "Package.swift",
        ] {
            let url = sandbox.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try path.write(to: url, atomically: true, encoding: .utf8)
        }

        try WarmSandboxes(directory: dir).prune(sandbox, keeping: ["Sources/App/Kept.swift"])

        let remaining = try FileManager.default.subpathsOfDirectory(atPath: sandbox.path).sorted()
        #expect(
            remaining == [
                ".build", ".build/debug", ".build/debug/App.o", ".xmr-derived-data", ".xmr-derived-data/Build",
                ".xmr-derived-data/Build/x", "Sources", "Sources/App", "Sources/App/Kept.swift", "lock",
            ]
        )
    }

    // MARK: - Private

    private func makeProject(in dir: URL) throws -> URL {
        let project = dir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "A.swift", in: project)
        return project
    }

    private static func holdLock(at url: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            "import fcntl, sys, time; f = open(sys.argv[1], 'w'); fcntl.flock(f, fcntl.LOCK_EX); "
                + "print('locked', flush=True); time.sleep(60)",
            url.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        _ = pipe.fileHandleForReading.readData(ofLength: 7)
        return process
    }
}
