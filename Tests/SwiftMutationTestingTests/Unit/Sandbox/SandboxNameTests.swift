import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxName")
struct SandboxNameTests {

    @Test("Given a name it made, when the owner is read back, then it is the process that made it")
    func nameCarriesTheOwner() {
        let name = SandboxName.make()

        #expect(name.hasPrefix(SandboxName.prefix))
        #expect(SandboxName.ownerPID(of: name) == getpid())
        #expect(SandboxName.isOwnerAlive(of: name))
    }

    @Test("Given the sandbox directory, when located, then it is a folder of its own inside the temporary root")
    func directoryIsItsOwnFolderInTemp() {
        let temp = SandboxName.temporaryRoot(environment: ProcessInfo.processInfo.environment).standardizedFileURL

        #expect(SandboxName.directory.deletingLastPathComponent().standardizedFileURL == temp)
        #expect(SandboxName.directory.standardizedFileURL != temp)
    }

    @Test("Given a non-empty TMPDIR, when the sandbox directory is located, then it lives under that path")
    func directoryHonorsTMPDIR() {
        let directory = SandboxName.directory(environment: ["TMPDIR": "/custom/tmp/"])

        #expect(directory.standardizedFileURL.path == "/custom/tmp/swift-mutation-testing")
    }

    @Test(
        "Given TMPDIR absent or empty, when the sandbox directory is located, then it falls back to the Foundation temp",
        arguments: [[String: String](), ["TMPDIR": ""]]
    )
    func directoryFallsBackWithoutTMPDIR(environment: [String: String]) {
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL

        #expect(SandboxName.directory(environment: environment).deletingLastPathComponent().standardizedFileURL == temp)
    }

    @Test("Given two names made in a row, when compared, then they differ")
    func namesAreUnique() {
        #expect(SandboxName.make() != SandboxName.make())
    }

    @Test("Given a name from a version that did not record the owner, when read, then it has none")
    func legacyNameHasNoOwner() {
        let name = "\(SandboxName.prefix)\(UUID().uuidString)"

        #expect(SandboxName.ownerPID(of: name) == nil)
        #expect(!SandboxName.isOwnerAlive(of: name))
    }

    @Test(
        "Given a name whose owner field is not a usable pid, when read, then it has none",
        arguments: [
            "xmr-0-\(UUID().uuidString)",
            "xmr--1-\(UUID().uuidString)",
            "xmr-notapid-\(UUID().uuidString)",
            "xmr-123",
            "xmr-",
        ]
    )
    func unusableOwnerFieldHasNoOwner(name: String) {
        #expect(SandboxName.ownerPID(of: name) == nil)
        #expect(!SandboxName.isOwnerAlive(of: name))
    }

    @Test("Given an old name whose UUID opens with digits, when read, then it is not mistaken for an owner")
    func legacyNameOpeningWithDigitsHasNoOwner() {
        let name = "\(SandboxName.prefix)00000001-1234-1234-1234-123456789ABC"

        #expect(SandboxName.ownerPID(of: name) == nil)
        #expect(!SandboxName.isOwnerAlive(of: name))
    }

    @Test("Given a name without the sandbox prefix, when read, then it has no owner")
    func foreignNameHasNoOwner() {
        #expect(SandboxName.ownerPID(of: "other-\(getpid())-\(UUID().uuidString)") == nil)
    }

    @Test("Given a name whose owner has exited, when asked, then the owner is not alive")
    func exitedOwnerIsNotAlive() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        let name = SandboxName.make(pid: process.processIdentifier)

        #expect(SandboxName.ownerPID(of: name) == process.processIdentifier)
        #expect(!SandboxName.isOwnerAlive(of: name))
    }
}
