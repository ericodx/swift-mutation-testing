import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Effective concurrency")
struct EffectiveConcurrencyTests {

    @Test("Given an SPM package, when concurrency is resolved, then the request is kept")
    func spmKeepsRequestedConcurrency() {
        // SPM runs its test bundle directly, so workers do not share a `.build` to queue on.
        let resolved = ConfigurationResolver.effectiveConcurrency(
            requested: 9,
            projectType: .spm,
            testingFramework: .swiftTesting
        )

        #expect(resolved == 9)
    }

    @Test("Given an Xcode scheme targeting macOS, when concurrency is resolved, then it is one")
    func macOSRunsOneWorker() {
        let resolved = ConfigurationResolver.effectiveConcurrency(
            requested: 9,
            projectType: .xcode(scheme: "App", destination: "platform=macOS"),
            testingFramework: .swiftTesting
        )

        #expect(resolved == 1)
    }

    @Test("Given an Xcode scheme on a simulator, when concurrency is resolved, then the request is kept")
    func simulatorKeepsRequestedConcurrency() {
        let resolved = ConfigurationResolver.effectiveConcurrency(
            requested: 9,
            projectType: .xcode(scheme: "App", destination: "platform=iOS Simulator,name=iPhone 16"),
            testingFramework: .swiftTesting
        )

        #expect(resolved == 9)
    }

    @Test("Given XCTest on a simulator, when concurrency is resolved, then it is one")
    func xctestRunsOneWorker() {
        let resolved = ConfigurationResolver.effectiveConcurrency(
            requested: 9,
            projectType: .xcode(scheme: "App", destination: "platform=iOS Simulator,name=iPhone 16"),
            testingFramework: .xctest
        )

        #expect(resolved == 1)
    }

    @Test("Given a request of one on a simulator, when concurrency is resolved, then it stays one")
    func keepsASingleWorkerRequest() {
        let resolved = ConfigurationResolver.effectiveConcurrency(
            requested: 1,
            projectType: .xcode(scheme: "App", destination: "platform=iOS Simulator,name=iPhone 16"),
            testingFramework: .swiftTesting
        )

        #expect(resolved == 1)
    }

    @Test("Given an SPM package, when a configuration is resolved end to end, then the request is kept")
    func resolvedConfigurationKeepsConcurrencyForSPM() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("// swift-tools-version: 6.0", named: "Package.swift", in: dir)

        let configuration = try ConfigurationResolver().resolve(
            cliArguments: ParsedArguments(projectPath: dir.path, build: .init(concurrency: 9)),
            fileValues: [:]
        )

        #expect(configuration.build.concurrency == 9)
    }
}
