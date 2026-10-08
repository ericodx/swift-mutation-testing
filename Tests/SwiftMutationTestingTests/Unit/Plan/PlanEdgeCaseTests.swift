import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Plans — edge cases")
struct PlanEdgeCaseTests {
    @Test("Given a planned mutant whose file is not among the sources, when materialized, then the file is missing")
    func aMutantWithoutItsFileIsRefused() {
        #expect(throws: PlanError.missingFile(file: "Sources/A.swift")) {
            try PlanMaterializer().materialize(
                plan: PlanStoreTests.plan, projectPath: "/p", sources: [], execution: Self.execution
            )
        }
    }

    @Test("Given a plan for an unknown kind of project, when materialized, then the type is named")
    func anUnknownProjectTypeIsRefusedWhenMaterialized() throws {
        let plan = try Self.plan(ofType: "cobol", mutants: [])

        #expect(throws: PlanError.unknownProjectType("cobol")) {
            try PlanMaterializer().materialize(plan: plan, projectPath: "/p", sources: [], execution: Self.execution)
        }
    }

    @Test("Given a plan for an unknown kind of project, when applied to a configuration, then the type is named")
    func anUnknownProjectTypeIsRefusedWhenApplied() throws {
        let plan = try Self.plan(ofType: "cobol", mutants: [])

        #expect(throws: PlanError.unknownProjectType("cobol")) {
            try makeRunnerConfiguration().applying(plan)
        }
    }

    @Test("Given a file of the current format version that is no plan, when read, then it is unreadable")
    func aCurrentVersionThatIsNoPlanIsUnreadable() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let path = dir.appendingPathComponent("plan.json").path
        try "{ \"formatVersion\" : \(Plan.formatVersion) }".write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: PlanError.unreadable(path: path)) { try PlanStore().read(from: path) }
    }

    @Test("Given a prefix of six characters that fits one fingerprint, when resolved, then that mutant is found")
    func aUniquePrefixFindsItsMutant() throws {
        let plan = try Self.plan(ofType: "spm", mutants: [Self.mutant("3f2a9c81"), Self.mutant("3f2b0000")])

        let (index, mutant) = try Reproducer.mutant(matching: "3f2a9c", in: plan)

        #expect(index == 0)
        #expect(mutant.fingerprint == "3f2a9c81")
    }

    @Test("Given a mutant whose file cannot be read, when its diff is made, then it names the change alone")
    func aDiffWithoutTheFileNamesTheChange() {
        let diff = Reproducer.diff(of: Self.mutant("3f2a9c81"), in: "/no/such/project")

        #expect(diff == "--- Sources/A.swift:1: < → <=")
    }

    @Test("Given a mutation that removes a line, when its diff is made, then it says the line count changes")
    func aDiffThatRemovesALineSaysSo() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let source = "func f() {\n    setUp(\n        1)\n    run()\n}\n"
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true
        )
        try source.write(to: dir.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
        let removed = "setUp(\n        1)"
        let start = source.utf8.distance(
            from: source.utf8.startIndex, to: try #require(source.range(of: removed)).lowerBound
        )
        let mutant = Plan.Mutant(
            fingerprint: "3f2a9c81", file: "Sources/A.swift", utf8Start: start, utf8End: start + removed.utf8.count,
            line: 2, column: 5, operatorIdentifier: "RemoveSideEffects", replacementKind: .removeStatement,
            original: removed, replacement: "", description: "remove setUp()", schematizable: true
        )

        let diff = Reproducer.diff(of: mutant, in: dir.path)

        #expect(diff.contains("-2:     setUp("))
        #expect(diff.hasSuffix("(the mutation changes the number of lines; see \(removed) → )"))
    }

    @Test("Given no result for the mutant, when the verdict is given, then it says none and fails")
    func noResultIsNoVerdict() {
        let (line, exit) = Reproducer.verdict(of: [])

        #expect(line == "Verdict: none — the mutant was not run")
        #expect(exit == .error)
    }

    @Test(
        "Given a result of each status, when the verdict is given, then it is described with its reason",
        arguments: [
            (ExecutionStatus.killed(by: "Suite.check"), Bool?.some(true), "Verdict: killed by Suite.check"),
            (.killedByCrash, nil, "Verdict: killed, the test process crashed (crash)"),
            (.timeout, false, "Verdict: timeout (timed out without activation)"),
            (.noCoverage, false, "Verdict: no coverage, no test ran the mutated code"),
            (.survived, true, "Verdict: survived"),
            (.unviable, nil, "Verdict: unviable, the mutant does not compile"),
        ]
    )
    func eachStatusIsDescribed(status: ExecutionStatus, activated: Bool?, expected: String) {
        let result = ExecutionResult(
            descriptor: makeMutantDescriptor(), status: status, testDuration: 0, activated: activated
        )

        let (line, exit) = Reproducer.verdict(of: [result])

        #expect(line == expected)
        #expect(exit == .success)
    }

    // MARK: - Helpers

    private static let execution = PlanMaterializer.ExecutionOptions(timeout: 60, concurrency: 1, noCache: true)

    private static func mutant(_ fingerprint: String) -> Plan.Mutant {
        Plan.Mutant(
            fingerprint: fingerprint, file: "Sources/A.swift", utf8Start: 0, utf8End: 1, line: 1, column: 1,
            operatorIdentifier: "RelationalOperatorReplacement", replacementKind: .binaryOperator, original: "<",
            replacement: "<=", description: "< → <=", schematizable: true
        )
    }

    private static func plan(ofType type: String, mutants: [Plan.Mutant]) throws -> Plan {
        let base = Plan(
            formatVersion: Plan.formatVersion, toolVersion: "1.7.0",
            project: Plan.Project(type: .spm, testTarget: nil),
            scope: Plan.Scope(sourcesPath: "Sources", excludePatterns: [], operators: []),
            files: [], mutants: mutants
        )
        var json = try #require(
            try JSONSerialization.jsonObject(with: PlanStore.encode(base)) as? [String: Any]
        )
        var project = try #require(json["project"] as? [String: Any])
        project["type"] = type
        json["project"] = project
        return try JSONDecoder().decode(Plan.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
