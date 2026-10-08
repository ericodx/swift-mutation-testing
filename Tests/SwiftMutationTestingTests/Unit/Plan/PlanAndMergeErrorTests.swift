import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("PlanError and MergeError")
struct PlanAndMergeErrorTests {
    @Test(
        "Given a plan error, when described, then the message names what went wrong and what to do",
        arguments: [
            (
                PlanError.notFound(path: "p.json"),
                "plan 'p.json' does not exist; write one with `swift-mutation-testing plan --output p.json`"
            ),
            (.unreadable(path: "p.json"), "plan 'p.json' could not be read as a swift-mutation-testing plan"),
            (
                .unsupportedVersion(path: "p.json", version: 9),
                "plan 'p.json' has format version 9, which this version cannot read; make it again"
            ),
            (.unknownProjectType("cobol"), "plan names a project type this version does not know: 'cobol'"),
            (.stale(file: "A.swift"), "plan is stale: A.swift changed since the plan was made; make the plan again"),
            (.missingFile(file: "A.swift"), "plan is stale: A.swift is no longer there; make the plan again"),
            (
                .corrupt(fingerprint: "3f2a", file: "A.swift"),
                "plan is corrupt: mutant 3f2a does not match the text at its position in A.swift"
            ),
            (.invalidShard("0/2"), "--shard must be i/n with 1 ≤ i ≤ n, not '0/2'"),
        ]
    )
    func planErrorsDescribeThemselves(error: PlanError, message: String) {
        #expect(error.errorDescription == message)
    }

    @Test(
        "Given a merge error, when described, then the message names the result at fault",
        arguments: [
            (
                MergeError.unreadableResult(path: "r.json"),
                "'r.json' could not be read as a swift-mutation-testing JSON report"
            ),
            (
                .noIdentity(path: "r.json"),
                "'r.json' names no plan (no config.planSha256); it was written by a version without plans"
            ),
            (
                .differentPlan(path: "r.json"),
                "'r.json' comes from a different plan; every result of a merge must run the same plan"
            ),
            (
                .duplicate(fingerprint: "3f2a", paths: ["a.json", "b.json"]),
                "mutant 3f2a has a verdict in more than one result: a.json, b.json"
            ),
            (
                .unknownStatus(path: "r.json", status: "Pending"),
                "'r.json' holds a status this version does not know: 'Pending'"
            ),
        ]
    )
    func mergeErrorsDescribeThemselves(error: MergeError, message: String) {
        #expect(error.errorDescription == message)
    }

    @Test(
        "Given a discovery error about the sources path, when described, then it names the path",
        arguments: [
            (FileDiscoveryError.sourcesPathNotFound("Sources/X"), "--sources-path 'Sources/X' does not exist"),
            (
                .sourcesPathNotSwift("README.md"),
                "--sources-path 'README.md' is neither a directory nor a .swift file"
            ),
        ]
    )
    func discoveryErrorsDescribeThemselves(error: FileDiscoveryError, message: String) {
        #expect(error.errorDescription == message)
    }

    @Test("Given one mutant missing, when described, then the noun is singular and nothing more is counted")
    func oneMissingMutantIsSingular() {
        let message = MergeError.missing(count: 1, sample: ["f0 (A.swift:1)"]).errorDescription

        #expect(message?.hasPrefix("1 mutant has no verdict in any result") == true)
        #expect(message?.contains("more") == false)
    }

    @Test("Given more mutants missing than the sample shows, when described, then the rest are counted")
    func missingMutantsBeyondTheSampleAreCounted() {
        let message = MergeError.missing(count: 7, sample: ["a", "b", "c", "d", "e"]).errorDescription

        #expect(message?.hasPrefix("7 mutants have no verdict in any result") == true)
        #expect(message?.contains("  … and 2 more") == true)
    }

    @Test("Given an Xcode plan's project, when read back, then its project container and type hold")
    func anXcodePlanProjectReadsBack() {
        let project = Plan.Project(
            type: .xcode(scheme: "App", destination: "platform=macOS"), testTarget: nil,
            container: .project("App.xcodeproj")
        )

        #expect(project.xcodeContainer == .project("App.xcodeproj"))
        #expect(project.projectType == .xcode(scheme: "App", destination: "platform=macOS"))
    }

    @Test("Given an Xcode plan's project with no scheme, when decoded, then it has no project type")
    func anXcodeProjectWithoutASchemeHasNoType() throws {
        let project = try JSONDecoder().decode(
            Plan.Project.self, from: Data(#"{"type": "xcode", "destination": "platform=macOS"}"#.utf8)
        )

        #expect(project.projectType == nil)
    }
}
