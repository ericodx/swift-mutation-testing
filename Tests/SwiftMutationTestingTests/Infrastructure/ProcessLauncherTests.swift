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
}
