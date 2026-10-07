import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    @Test("Given the capture file cannot be read back, when the process ends, then the output is empty")
    func anUnreadableCaptureYieldsEmptyOutput() async throws {
        struct Unreadable: Error {}

        let runner = ProcessRunner(onTimeout: { _ in }, readCapturedOutput: { _ in throw Unreadable() })

        let result = try await runner.launchCapturing(echo("hello"))

        #expect(result.exitCode == 0)
        #expect(result.output == "")
    }

    @Test("Given the capture file reads back, when the process ends, then the output is what it wrote")
    func aReadableCaptureYieldsTheOutput() async throws {
        let runner = ProcessRunner(onTimeout: { _ in })

        let result = try await runner.launchCapturing(echo("hello"))

        #expect(result.output == "hello\n")
    }

    @Test("Given output cut in the middle of a character, when the process ends, then everything before it is kept")
    func anOutputCutMidCharacterIsKept() async throws {
        let runner = ProcessRunner(onTimeout: { _ in })
        let failure = "Test Case '-[MySuite myTest]' failed (0.001 seconds)."

        let result = try await runner.launchCapturing(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '%s\\n\\342\\234' \"$0\"; exit 1", failure],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        )

        #expect(result.output.hasPrefix(failure + "\n"))
        #expect(TestOutputParser().parse(result.output) == .killed(by: "MySuite.myTest"))
    }

    private func echo(_ text: String) -> ProcessRequest {
        ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: [text],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )
    }

    @Test("Given a stop rule, when the process prints a marker, then it is stopped and reports the rule's exit code")
    func aMarkerStopsTheProcessEarly() async throws {
        let runner = ProcessRunner(onTimeout: { pid in kill(-pid, SIGTERM) })
        let script = "echo \"Test Case '-[SuiteTests aCheck]' failed (0.001 seconds).\"; sleep 30"
        let start = ContinuousClock.now

        let result = try await runner.launchCapturing(shell(script, timeout: 20).stopping(at: .firstTestFailure))

        #expect(result.exitCode == 1)
        #expect(result.output.contains("aCheck"))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("Given a stop rule, when the marker arrives split across two writes, then it is still seen")
    func aMarkerSplitAcrossWritesIsStillSeen() async throws {
        let runner = ProcessRunner(onTimeout: { pid in kill(-pid, SIGTERM) })
        let script =
            "printf \"Test Case '-[SuiteTests aCheck]' fai\"; sleep 0.4; printf \"led (0.1 seconds).\\n\"; sleep 30"

        let result = try await runner.launchCapturing(shell(script, timeout: 20).stopping(at: .firstTestFailure))

        #expect(result.exitCode == 1)
    }

    @Test("Given a stop rule, when a line only quotes a failure, then the process runs to its own end")
    func aQuotedFailureDoesNotStopTheProcess() async throws {
        let runner = ProcessRunner(onTimeout: { pid in kill(-pid, SIGTERM) })
        let line = #"◇ Test case passing 1 argument l → "✘ Test "a" recorded an issue at F.swift:3:9" to "t" started."#
        let script = "echo '\(line)'; sleep 1; echo done; exit 0"

        let result = try await runner.launchCapturing(shell(script, timeout: 20).stopping(at: .firstTestFailure))

        #expect(result.exitCode == 0)
        #expect(result.output.hasSuffix("done\n"))
    }

    @Test("Given a stop rule, when no marker is printed, then the process runs to its own end")
    func noMarkerLetsTheProcessFinish() async throws {
        let runner = ProcessRunner(onTimeout: { pid in kill(-pid, SIGTERM) })

        let request = shell("echo all good; exit 3", timeout: 20).stopping(at: .firstTestFailure)

        let result = try await runner.launchCapturing(request)

        #expect(result.exitCode == 3)
        #expect(result.output == "all good\n")
    }

    @Test("Given a stop rule and a process that never prints a marker, when the timeout passes, then it is a timeout")
    func theTimeoutStillAppliesUnderAStopRule() async throws {
        let runner = ProcessRunner(onTimeout: { pid in kill(-pid, SIGTERM) })

        let request = shell("echo waiting; sleep 30", timeout: 0.5).stopping(at: .firstTestFailure)

        let result = try await runner.launchCapturing(request)

        #expect(result.exitCode == -1)
    }

    @Test("Given a capturing run in flight, when its process groups are killed, then the run ends at once")
    func aCapturingRunInFlightIsTracked() async throws {
        let processGroups = ProcessGroupRegistry()
        let runner = ProcessRunner(onTimeout: { _ in }, processGroups: processGroups)
        let start = ContinuousClock.now

        async let result = runner.launchCapturing(shell("sleep 30", timeout: 60))
        try await Task.sleep(for: .milliseconds(500))
        processGroups.killAll()

        #expect(try await result.exitCode == SIGKILL)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("Given a run in flight, when its process groups are killed, then the run ends at once")
    func aRunInFlightIsTracked() async throws {
        let processGroups = ProcessGroupRegistry()
        let runner = ProcessRunner(onTimeout: { _ in }, processGroups: processGroups)
        let start = ContinuousClock.now

        async let exitCode = runner.launch(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 60
        )
        try await Task.sleep(for: .milliseconds(500))
        processGroups.killAll()

        #expect(try await exitCode == SIGKILL)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("Given a run that has ended, when process groups are killed, then its pid is no longer signalled")
    func aFinishedRunIsNoLongerTracked() async throws {
        let processGroups = ProcessGroupRegistry()
        let recorder = RecordingKill()
        let runner = ProcessRunner(onTimeout: { _ in }, processGroups: processGroups)

        _ = try await runner.launchCapturing(echo("done"))
        _ = try await runner.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )
        processGroups.killAll(kill: recorder.asKill)

        #expect(recorder.recorded.isEmpty)
    }

    @Test("Given a capturing run whose task is already cancelled, when it launches, then the process never runs")
    func aCancelledCapturingRunStartsNoProcess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let marker = dir.appendingPathComponent("ran").path
        let runner = ProcessRunner(onTimeout: { _ in })
        let request = shell("touch '\(marker)'", timeout: 10)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.launchCapturing(request)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("Given a run whose task is already cancelled, when it launches, then the process never runs")
    func aCancelledRunStartsNoProcess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let marker = dir.appendingPathComponent("ran").path
        let runner = ProcessRunner(onTimeout: { _ in })

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.launch(
                executableURL: URL(fileURLWithPath: "/usr/bin/touch"),
                arguments: [marker],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("Given a launched process, when it runs, then it leads a process group of its own")
    func aLaunchedProcessLeadsItsOwnGroup() async throws {
        let runner = ProcessRunner(onTimeout: { _ in })

        let result = try await runner.launchCapturing(shell("echo $$ $(ps -o pgid= -p $$)", timeout: 10))
        let ids = result.output.split(whereSeparator: \.isWhitespace)

        #expect(ids.count == 2)
        #expect(ids.first == ids.last)
    }

    @Test("Given a process that leads its own group or has exited, when its group is checked, then nothing is reported")
    func aGroupLeaderOrAnExitedProcessIsNotReported() {
        let warnings = Mutex<[String]>([])
        let warning = OnceWarning { line in warnings.withLock { $0.append(line) } }

        ProcessRunner.checkOwnGroup(4242, groupOf: { $0 }, warning: warning)
        ProcessRunner.checkOwnGroup(4242, groupOf: { _ in -1 }, warning: warning)

        #expect(warnings.withLock { $0 }.isEmpty)
    }

    @Test("Given processes that share their parent's group, when their groups are checked, then one warning is shown")
    func aProcessOutsideItsOwnGroupIsReportedOnce() {
        let warnings = Mutex<[String]>([])
        let warning = OnceWarning { line in warnings.withLock { $0.append(line) } }

        ProcessRunner.checkOwnGroup(4242, groupOf: { _ in 1 }, warning: warning)
        ProcessRunner.checkOwnGroup(4243, groupOf: { _ in 1 }, warning: warning)

        #expect(warnings.withLock { $0 }.count == 1)
        #expect(warnings.withLock { $0 }.first?.contains("does not lead its own process group") == true)
    }

    private func shell(_ script: String, timeout: Double) -> ProcessRequest {
        ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: timeout
        )
    }
}
