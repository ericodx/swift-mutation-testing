import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProcessLauncher")
struct ProcessLauncherTests {
    private let launcher = ProcessLauncher()

    @Test("Given a successful executable, when launched, then returns zero exit code")
    func launchReturnsSuccessExitCode() async throws {
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(exitCode == 0)
    }

    @Test("Given a failing executable, when launched, then returns non-zero exit code")
    func launchReturnsFailureExitCode() async throws {
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(exitCode != 0)
    }

    @Test("Given echo command, when launched capturing, then output contains the argument")
    func launchCapturingReturnsStdout() async throws {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello world"],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("hello world"))
    }

    @Test("Given environment variables, when launched capturing, then process receives the variables")
    func launchCapturingPassesEnvironment() async throws {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $TEST_VAR"],
            environment: ["TEST_VAR": "expected_value"],
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("expected_value"))
    }

    @Test("Given stderr output, when launched capturing, then stderr is included in output")
    func launchCapturingCapturesStderr() async throws {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo error_text >&2"],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(result.output.contains("error_text"))
    }

    @Test("Given long-running process and short timeout, when timeout expires, then returns minus one exit code")
    func launchTimesOutAndReturnsMinus1() async throws {
        let exitCode = try await launcher.launch(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 0.5
        )

        #expect(exitCode == -1)
    }

    @Test("Given non-existent executable, when launched, then throws")
    func launchThrowsForNonExistentExecutable() async {
        await #expect(throws: (any Error).self) {
            try await launcher.launch(
                executableURL: URL(fileURLWithPath: "/nonexistent/binary"),
                arguments: [],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        }
    }

    @Test("Given non-existent executable, when launchCapturing called, then throws")
    func launchCapturingThrowsForNonExistentExecutable() async {
        await #expect(throws: (any Error).self) {
            try await launcher.launchCapturing(
                executableURL: URL(fileURLWithPath: "/nonexistent/binary"),
                arguments: [],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )
        }
    }

    @Test("Given long-running process and short timeout, when launchCapturing times out, then returns minus one")
    func launchCapturingTimesOut() async throws {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 0.5
        )

        #expect(result.exitCode == -1)
    }

    @Test("Given task is cancelled while launch running, when cancelled, then process is terminated")
    func cancelledLaunchTerminatesProcess() async throws {
        let task = Task {
            try await launcher.launch(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["60"],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 60
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let exitCode = try await task.value
        #expect(exitCode == -1)
    }

    @Test("Given additionalEnvironment, when launched capturing, then process receives merged variable")
    func launchCapturingMergesAdditionalEnvironment() async throws {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $EXTRA_VAR"],
            environment: nil,
            additionalEnvironment: ["EXTRA_VAR": "merged_value"],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("merged_value"))
    }

    @Test("Given task is cancelled while launchCapturing running, when cancelled, then process is terminated")
    func cancelledLaunchCapturingTerminatesProcess() async throws {
        let task = Task {
            try await launcher.launchCapturing(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["60"],
                environment: nil,
                additionalEnvironment: [:],
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 60
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let result = try await task.value
        #expect(result.exitCode == -1)
    }
}
