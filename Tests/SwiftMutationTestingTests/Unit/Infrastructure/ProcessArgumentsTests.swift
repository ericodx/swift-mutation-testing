import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProcessArguments")
struct ProcessArgumentsTests {

    @Test("Given a KERN_PROCARGS2 buffer, when parsed, then argv comes back without the path or environment")
    func parsesArgvFromTheBuffer() {
        let buffer = procargs(executable: "/bin/tool", arguments: ["tool", "--flag", "value"], environment: ["A=1"])

        #expect(ProcessArguments.parse(buffer) == ["tool", "--flag", "value"])
    }

    @Test("Given a buffer too short to hold argc, when parsed, then nothing is returned")
    func aTruncatedBufferYieldsNothing() {
        #expect(ProcessArguments.parse([1, 0]) == nil)
    }

    @Test("Given a buffer that ends before argc arguments, when parsed, then the arguments present are returned")
    func aBufferShortOfArgumentsYieldsWhatItHas() {
        var buffer = procargs(executable: "/bin/tool", arguments: ["tool"], environment: [])
        buffer.replaceSubrange(0 ..< 4, with: withUnsafeBytes(of: Int32(5)) { Array($0) })

        #expect(ProcessArguments.parse(buffer) == ["tool"])
    }

    @Test("Given an argument that is not UTF-8, when parsed, then it comes back empty and the others intact")
    func anArgumentThatIsNotTextIsEmpty() {
        var buffer = withUnsafeBytes(of: Int32(2)) { Array($0) }
        buffer += Array("/bin/tool".utf8) + [0, 0]
        buffer += Array("tool".utf8) + [0]
        buffer += [0xFF, 0xFE, 0]

        #expect(ProcessArguments.parse(buffer) == ["tool", ""])
    }

    @Test("Given a running process of ours, when its arguments are read, then they are its argv")
    func readsTheArgumentsOfALiveProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        try await Task.sleep(for: .milliseconds(200))

        #expect(ProcessArguments.read(pid: process.processIdentifier) == ["/bin/sleep", "30"])
    }

    @Test("Given the buffer size cannot be queried, when arguments are read, then nothing is returned")
    func anUnsizableBufferYieldsNothing() {
        let failing: SystemCalls.Sysctl = { _, _, _, _, _, _ in -1 }

        #expect(ProcessArguments.read(pid: 2, sysctl: failing) == nil)
    }

    @Test("Given the buffer cannot be read after sizing, when arguments are read, then nothing is returned")
    func anUnreadableBufferYieldsNothing() {
        var calls = 0
        let failingOnRead: SystemCalls.Sysctl = { _, _, _, size, _, _ in
            calls += 1
            guard calls == 1 else { return -1 }
            size?.pointee = 64
            return 0
        }

        #expect(ProcessArguments.read(pid: 2, sysctl: failingOnRead) == nil)
        #expect(calls == 2)
    }

    // MARK: - Private

    private func procargs(executable: String, arguments: [String], environment: [String]) -> [UInt8] {
        var buffer = withUnsafeBytes(of: Int32(arguments.count)) { Array($0) }
        buffer += Array(executable.utf8) + [0, 0, 0]
        for entry in arguments + environment {
            buffer += Array(entry.utf8) + [0]
        }
        return buffer
    }
}
