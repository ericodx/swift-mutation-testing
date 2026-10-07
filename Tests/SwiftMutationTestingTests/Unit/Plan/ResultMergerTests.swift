import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ResultMerger")
struct ResultMergerTests {
    @Test("Given two results of one plan covering every mutant, when merged, then each verdict is rebuilt")
    func verdictsAreRebuiltFromTheResults() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let plan = Self.plan
        let first = try Self.writeResult(
            in: dir, name: "a.json", plan: plan,
            verdicts: [(Self.mutants[0], .killed(by: "Suite.a"), true), (Self.mutants[1], .survived, true)]
        )
        let second = try Self.writeResult(
            in: dir, name: "b.json", plan: plan, verdicts: [(Self.mutants[2], .killedByCrash, false)]
        )

        let merged = try ResultMerger().merge(resultPaths: [first, second], plan: plan, projectPath: dir.path)

        #expect(merged.results.map(\.descriptor.id) == (0 ..< 3).map(MutantID.make(index:)))
        #expect(merged.results.map(\.status) == [.killed(by: "Suite.a"), .survived, .killedByCrash])
        #expect(merged.results.map(\.activated) == [true, true, false])
        #expect(merged.results.map(\.descriptor.fingerprint) == Self.mutants.map(\.fingerprint))
        #expect(merged.results[0].descriptor.filePath.hasSuffix("/Sources/A.swift"))
        #expect(abs(merged.totalDuration - 0.3) < 0.000_001)
        #expect(merged.planSha256 == (try PlanStore.sha256(of: plan)))
        let hashes = PlanMaterializer.fileHashes(of: plan)
        #expect(merged.results.map(\.descriptor.sourceContentHash) == Self.mutants.map { hashes[$0.file] })
    }

    @Test("Given a result of another plan, when merged, then it is refused by name")
    func anotherPlanIsRefused() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let other = Plan(
            formatVersion: Plan.formatVersion, toolVersion: "0", project: Self.plan.project, scope: Self.plan.scope,
            files: Self.plan.files, mutants: Array(Self.plan.mutants.prefix(2))
        )
        let path = try Self.writeResult(
            in: dir, name: "a.json", plan: other, verdicts: [(Self.mutants[0], .survived, true)])

        #expect(throws: MergeError.differentPlan(path: path)) {
            try ResultMerger().merge(resultPaths: [path], plan: Self.plan, projectPath: dir.path)
        }
    }

    @Test("Given a mutant with a verdict in two results, when merged, then both files are named")
    func aDuplicateIsRefused() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let first = try Self.writeResult(
            in: dir, name: "a.json", plan: Self.plan, verdicts: [(Self.mutants[0], .survived, true)])
        let second = try Self.writeResult(
            in: dir, name: "b.json", plan: Self.plan, verdicts: [(Self.mutants[0], .survived, true)])

        #expect(throws: MergeError.duplicate(fingerprint: "f0", paths: [first, second])) {
            try ResultMerger().merge(resultPaths: [first, second], plan: Self.plan, projectPath: dir.path)
        }
    }

    @Test("Given a mutant without any verdict, when merged, then it is reported and there is no score")
    func aMissingMutantHasNoScore() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = try Self.writeResult(
            in: dir, name: "a.json", plan: Self.plan, verdicts: [(Self.mutants[0], .survived, true)])

        #expect(throws: MergeError.missing(count: 2, sample: ["f1 (Sources/A.swift:2)", "f2 (Sources/B.swift:1)"])) {
            try ResultMerger().merge(resultPaths: [path], plan: Self.plan, projectPath: dir.path)
        }
    }

    @Test("Given a result without an identity or not a report at all, when merged, then each is refused")
    func unreadableResultsAreRefused() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let notJSON = dir.appendingPathComponent("x.json").path
        try "nope".write(toFile: notJSON, atomically: true, encoding: .utf8)
        let noIdentity = dir.appendingPathComponent("y.json").path
        try JsonReporter(outputPath: noIdentity, projectRoot: dir.path).report(
            RunnerSummary(results: [], totalDuration: 0))

        #expect(throws: MergeError.unreadableResult(path: notJSON)) {
            try ResultMerger().merge(resultPaths: [notJSON], plan: Self.plan, projectPath: dir.path)
        }
        #expect(throws: MergeError.noIdentity(path: noIdentity)) {
            try ResultMerger().merge(resultPaths: [noIdentity], plan: Self.plan, projectPath: dir.path)
        }
    }

    // MARK: - Fixture

    static let mutants = [
        Plan.Mutant(
            fingerprint: "f0", file: "Sources/A.swift", utf8Start: 0, utf8End: 1, line: 1, column: 1,
            operatorIdentifier: "SwapTernary", replacementKind: .swapTernary, original: "a", replacement: "b",
            description: "", schematizable: true
        ),
        Plan.Mutant(
            fingerprint: "f1", file: "Sources/A.swift", utf8Start: 5, utf8End: 6, line: 2, column: 1,
            operatorIdentifier: "SwapTernary", replacementKind: .swapTernary, original: "a", replacement: "b",
            description: "", schematizable: true
        ),
        Plan.Mutant(
            fingerprint: "f2", file: "Sources/B.swift", utf8Start: 0, utf8End: 1, line: 1, column: 1,
            operatorIdentifier: "NegateConditional", replacementKind: .wrapWithNegation, original: "a",
            replacement: "!a", description: "", schematizable: false
        ),
    ]

    static let plan = Plan(
        formatVersion: Plan.formatVersion, toolVersion: "0", project: Plan.Project(type: .spm, testTarget: nil),
        scope: Plan.Scope(
            sourcesPath: "Sources", excludePatterns: [], operators: ["SwapTernary", "NegateConditional"]),
        files: [Plan.File(path: "Sources/A.swift", sha256: "ha"), Plan.File(path: "Sources/B.swift", sha256: "hb")],
        mutants: mutants
    )

    static func writeResult(
        in dir: URL, name: String, plan: Plan, verdicts: [(Plan.Mutant, ExecutionStatus, Bool?)]
    ) throws -> String {
        let results = verdicts.map { mutant, status, activated in
            ExecutionResult(
                descriptor: makeMutantDescriptor(
                    id: MutantID.make(index: plan.mutants.firstIndex(of: mutant) ?? 0),
                    filePath: dir.appendingPathComponent(mutant.file).path, line: mutant.line, column: mutant.column,
                    utf8Offset: mutant.utf8Start, originalText: mutant.original, mutatedText: mutant.replacement,
                    operatorIdentifier: mutant.operatorIdentifier, fingerprint: mutant.fingerprint
                ),
                status: status, testDuration: 0.1, activated: activated
            )
        }
        let path = dir.appendingPathComponent(name).path
        try JsonReporter(outputPath: path, projectRoot: dir.path).report(
            RunnerSummary(results: results, totalDuration: 1),
            identity: RunIdentity(planSha256: try PlanStore.sha256(of: plan), shard: nil)
        )
        return path
    }
}
