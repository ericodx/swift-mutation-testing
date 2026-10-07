import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationResolver — file values")
struct ConfigurationResolverFileValueTests {

    @Test(
        "Given a timeout in the file that is not a positive number, when resolved, then it is rejected",
        arguments: [["timeout": "0"], ["timeout": "-5"], ["timeout": "soon"], ["build-timeout": "0"]]
    )
    func anInvalidTimeoutIsRejected(fileValues: [String: String]) {
        #expect(throws: UsageError.self) {
            try resolve(fileValues: fileValues)
        }
    }

    @Test("Given a zero concurrency in the file, when resolved, then the error names the file, not the flag")
    func aZeroConcurrencyInTheFileNamesTheFile() {
        let error = #expect(throws: UsageError.self) {
            try resolve(fileValues: ["concurrency": "0"])
        }

        #expect(error?.message == "concurrency in .swift-mutation-testing.yml must be >= 1")
    }

    @Test("Given a concurrency in the file that is not a number, when resolved, then it is rejected")
    func aConcurrencyThatIsNotANumberIsRejected() {
        #expect(throws: UsageError.self) {
            try resolve(fileValues: ["concurrency": "many"])
        }
    }

    @Test(
        "Given a flag in the file written as YAML allows, when resolved, then it is read as such",
        arguments: [("yes", true), ("on", true), ("True", true), ("no", false), ("off", false), ("false", false)]
    )
    func flagsAcceptTheYAMLSpellings(raw: String, expected: Bool) throws {
        let result = try resolve(fileValues: ["quiet": raw, "no-cache": raw])

        #expect(result.reporting.quiet == expected)
        #expect(result.build.noCache == expected)
    }

    @Test("Given a flag in the file that is neither true nor false, when resolved, then it is rejected")
    func anUnreadableFlagIsRejected() {
        let error = #expect(throws: UsageError.self) {
            try resolve(fileValues: ["quiet": "maybe"])
        }

        #expect(error?.message == "quiet in .swift-mutation-testing.yml must be true or false")
    }

    @Test("Given misspelled keys in the file, when resolved, then each one is warned about")
    func unknownKeysAreWarnedAbout() throws {
        let warnings = Mutex<[String]>([])

        _ = try resolve(
            fileValues: ["timout": "60", "testTarget": "AppTests", "timeout": "60", "html-output": "r.html"],
            warn: { line in warnings.withLock { $0.append(line) } }
        )

        #expect(
            warnings.withLock { $0 } == [
                "Warning: unknown key 'testTarget' in .swift-mutation-testing.yml is ignored",
                "Warning: unknown key 'timout' in .swift-mutation-testing.yml is ignored",
            ]
        )
    }

    @Test(
        "Given every key init writes, when checked, then each one is a known key",
        arguments: [
            DetectedProject.empty,
            DetectedProject(kind: .spm(testTargets: ["AppTests"]), testTarget: "AppTests"),
        ]
    )
    func everyGeneratedKeyIsKnown(project: DetectedProject) throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try StandardOutput.$capture.withValue(StandardOutput.Capture()) {
            try ConfigurationFileWriter().write(to: dir.path, project: project)
        }
        let content = try String(
            contentsOf: dir.appendingPathComponent(ConfigurationResolver.fileName), encoding: .utf8)
        let keys = content.components(separatedBy: .newlines).compactMap { line -> String? in
            let uncommented = line.hasPrefix("# ") ? String(line.dropFirst(2)) : line
            guard
                let colon = uncommented.firstIndex(of: ":"),
                !uncommented.hasPrefix(" "),
                !uncommented.hasPrefix("-")
            else { return nil }
            let key = String(uncommented[..<colon])
            return key.allSatisfy { $0.isLowercase || $0 == "-" } ? key : nil
        }

        #expect(!keys.isEmpty)
        #expect(Set(keys).subtracting(["mutators"]).isSubset(of: ConfigurationResolver.fileKeys))
    }

    // MARK: - Private

    @discardableResult
    private func resolve(
        fileValues: [String: String],
        warn: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> RunnerConfiguration {
        var resolver = ConfigurationResolver()
        resolver.warn = warn
        return try resolver.resolve(
            cliArguments: ParsedArguments(
                projectPath: "/tmp", build: .init(scheme: "App", destination: "platform=macOS")),
            fileValues: fileValues
        )
    }
}
