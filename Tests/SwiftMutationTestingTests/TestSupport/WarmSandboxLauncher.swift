import Foundation

@testable import SwiftMutationTesting

actor WarmSandboxLauncher: ProcessLaunching {
    private let failsWarmBuildsAfterTheFirstRoot: Bool
    private let failsEveryBuild: Bool
    private let laterWarmBuildsWaitForTheFirstTest: Bool
    private let testRunsTake: [Duration]
    private var roots: [String] = []
    private var brokenRoots: Set<String> = []
    private var inFlightBuilds = 0
    private(set) var maxInFlightBuilds = 0
    private(set) var testRunsByRoot: [String: Int] = [:]
    private(set) var firstTestStartedAt: Date?
    private(set) var warmBuildsFinishedAt: [Date] = []

    init(
        failsWarmBuildsAfterTheFirstRoot: Bool = false,
        failsEveryBuild: Bool = false,
        laterWarmBuildsWaitForTheFirstTest: Bool = false,
        testRunsTake: [Duration] = [.zero]
    ) {
        self.failsWarmBuildsAfterTheFirstRoot = failsWarmBuildsAfterTheFirstRoot
        self.failsEveryBuild = failsEveryBuild
        self.laterWarmBuildsWaitForTheFirstTest = laterWarmBuildsWaitForTheFirstTest
        self.testRunsTake = testRunsTake
    }

    var buildRoots: [String] { roots }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()
        let root = request.workingDirectoryURL.path

        if request.arguments.first == "build" {
            let isWarmBuild = !roots.contains(root)
            if isWarmBuild { roots.append(root) }

            if failsEveryBuild || (failsWarmBuildsAfterTheFirstRoot && isWarmBuild && roots.count > 1) {
                brokenRoots.insert(root)
            }

            inFlightBuilds += 1
            maxInFlightBuilds = max(maxInFlightBuilds, inFlightBuilds)
            if isWarmBuild, laterWarmBuildsWaitForTheFirstTest, roots.first != root {
                try await waitForTheFirstTest()
            } else {
                try await Task.sleep(for: .milliseconds(isWarmBuild ? 30 : 1))
            }
            inFlightBuilds -= 1
            if isWarmBuild { warmBuildsFinishedAt.append(Date()) }

            return brokenRoots.contains(root) ? (1, "error: warm build broke in \(root)") : (0, "")
        }

        if request.arguments.first == "test" || request.arguments.first == "xctest"
            || request.executableURL.lastPathComponent == "swiftpm-testing-helper"
        {
            if firstTestStartedAt == nil { firstTestStartedAt = Date() }
            testRunsByRoot[root, default: 0] += 1
            try await Task.sleep(for: duration(of: testRunsTake, for: root))
        }

        return (0, "")
    }

    // MARK: - Private

    private func duration(of durations: [Duration], for root: String) -> Duration {
        let index = roots.firstIndex(of: root) ?? durations.count - 1
        return durations[min(index, durations.count - 1)]
    }

    private func waitForTheFirstTest() async throws {
        let deadline = Date().addingTimeInterval(3)
        while firstTestStartedAt == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
