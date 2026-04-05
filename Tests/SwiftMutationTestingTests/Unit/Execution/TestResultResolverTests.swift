import Testing

@testable import SwiftMutationTesting

@Suite("TestResultResolver")
struct TestResultResolverTests {
    @Test("Given SPM project type and exit code 0, when resolved, then outcome is passed")
    func spmExitCodeZeroResolvesToPassed() async throws {
        let resolver = TestResultResolver(launcher: MockProcessLauncher(exitCode: 0))
        let launch = TestLaunchResult(exitCode: 0, output: "", xcresultPath: "", duration: 1)

        let outcome = try await resolver.resolve(launch: launch, projectType: .spm, timeout: 60)

        #expect(outcome == .testsSucceeded)
    }

    @Test("Given SPM project type and exit code 1 with failure, when resolved, then outcome is failed")
    func spmExitCodeOneWithFailureResolvesToFailed() async throws {
        let resolver = TestResultResolver(launcher: MockProcessLauncher(exitCode: 0))
        let output = #"Test "myTest" failed after 0.001 seconds."#
        let launch = TestLaunchResult(exitCode: 1, output: output, xcresultPath: "", duration: 1)

        let outcome = try await resolver.resolve(launch: launch, projectType: .spm, timeout: 60)

        #expect(outcome == .testsFailed(failingTest: "myTest"))
    }
}
