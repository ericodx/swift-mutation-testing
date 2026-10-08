import Foundation

@testable import SwiftMutationTesting

actor ActivationScriptLauncher: ProcessLaunching {
    struct TestRun: Sendable {
        let exitCode: Int32
        let output: String
        let writesMarker: Bool
        var throwing = false

        static let throwsError = TestRun(exitCode: 0, output: "", writesMarker: false, throwing: true)

        static func passes(writesMarker: Bool) -> TestRun {
            TestRun(exitCode: 0, output: "", writesMarker: writesMarker)
        }

        static func fails(_ test: String, writesMarker: Bool) -> TestRun {
            TestRun(
                exitCode: 1, output: "✘ Test \"\(test)\" failed after 0.001 seconds with 1 issue.",
                writesMarker: writesMarker
            )
        }
    }

    private let mutatedFile: String
    private let failsInstrumentedBuild: Bool
    private var testRuns: [TestRun]
    private(set) var builtInstrumented: [Bool] = []
    private(set) var testEnvironments: [[String: String]] = []

    init(mutatedFile: String, failsInstrumentedBuild: Bool = false, testRuns: [TestRun]) {
        self.mutatedFile = mutatedFile
        self.failsInstrumentedBuild = failsInstrumentedBuild
        self.testRuns = testRuns
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String) {
        switch request.arguments.first {
        case "build", "build-for-testing":
            let file = request.workingDirectoryURL.appendingPathComponent(mutatedFile)
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let instrumented = content.contains(".activating(") || content.contains(".activated()")
            builtInstrumented.append(instrumented)
            return instrumented && failsInstrumentedBuild ? (1, "error: cannot convert value") : (0, "")

        case "test", "test-without-building":
            testEnvironments.append(request.additionalEnvironment)
            let run = testRuns.isEmpty ? TestRun.passes(writesMarker: false) : testRuns.removeFirst()
            if run.throwing { throw CocoaError(.fileReadNoSuchFile) }
            let markerPath = request.additionalEnvironment.first {
                $0.key.hasSuffix(ActivationMarker.environmentVariable)
            }
            if run.writesMarker, let path = markerPath?.value {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            return (run.exitCode, run.output)

        default:
            return (0, "")
        }
    }
}
