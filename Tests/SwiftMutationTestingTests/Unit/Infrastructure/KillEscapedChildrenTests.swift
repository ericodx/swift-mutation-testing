import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("killEscapedChildren")
struct KillEscapedChildrenTests {
    @Test("Given process with sandbox name in arguments, when called, then process is killed")
    func killsProcessMatchingSandboxName() async throws {
        let marker = "xmr-test-\(UUID().uuidString.prefix(8))"
        let markerFile = "/tmp/\(marker)"
        FileManager.default.createFile(atPath: markerFile, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: markerFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = ["-f", markerFile]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        try await Task.sleep(for: .milliseconds(100))
        #expect(process.isRunning)

        killEscapedChildren(sandboxPath: "/tmp/\(marker)")

        try await Task.sleep(for: .milliseconds(200))
        #expect(!process.isRunning)
    }

    @Test("Given sandbox name without xmr prefix, when called, then no processes are killed")
    func doesNotKillWhenSandboxNameLacksPrefix() async throws {
        let marker = "other-test-\(UUID().uuidString.prefix(8))"
        let markerFile = "/tmp/\(marker)"
        FileManager.default.createFile(atPath: markerFile, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: markerFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = ["-f", markerFile]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        try await Task.sleep(for: .milliseconds(100))
        #expect(process.isRunning)

        killEscapedChildren(sandboxPath: "/tmp/\(marker)")

        try await Task.sleep(for: .milliseconds(200))
        #expect(process.isRunning)
    }
}
