import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("PlanMaterializer")
struct PlanMaterializerTests {
    @Test("Given a plan written and read back, when materialized, then the input equals the direct flow's")
    func thePlanMaterializesToTheDirectFlowsInput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let input = Self.discoveryInput(for: dir)

        let direct = try await DiscoveryPipeline().run(input: input)
        let planPath = dir.appendingPathComponent("plan.json").path
        try PlanStore().write(try await Planner().plan(input: input).plan, to: planPath)
        let materialized = try await PlanMaterializer().materialize(
            plan: try PlanStore().read(from: planPath), projectPath: dir.path, execution: Self.execution
        )

        let byPath = { (files: [SchematizedFile]) in
            files.map { [$0.originalPath, $0.schematizedContent] }.sorted { $0[0] < $1[0] }
        }
        #expect(byPath(materialized.schematizedFiles) == byPath(direct.schematizedFiles))
        #expect(materialized.mutants.map(\.id) == direct.mutants.map(\.id))
        #expect(materialized.mutants.map(\.fingerprint) == direct.mutants.map(\.fingerprint))
        #expect(materialized.mutants.map(\.utf8Offset) == direct.mutants.map(\.utf8Offset))
        #expect(materialized.mutants.map(\.mutatedSourceContent) == direct.mutants.map(\.mutatedSourceContent))
        #expect(materialized.mutants.map(\.sourceContentHash) == direct.mutants.map(\.sourceContentHash))
        #expect(materialized.importStyle == direct.importStyle)
        #expect(materialized.projectType == direct.projectType)
    }

    @Test("Given a file edited after the plan, when materialized, then the plan is stale")
    func anEditedFileMakesThePlanStale() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let plan = try await Planner().plan(input: Self.discoveryInput(for: dir)).plan
        try "func a() -> Bool { false }\n".write(
            to: dir.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8
        )

        await #expect(throws: PlanError.stale(file: "Sources/A.swift")) {
            _ = try await PlanMaterializer().materialize(plan: plan, projectPath: dir.path, execution: Self.execution)
        }
    }

    @Test("Given a file removed after the plan, when materialized, then the plan names it")
    func aRemovedFileMakesThePlanStale() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let plan = try await Planner().plan(input: Self.discoveryInput(for: dir)).plan
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Sources/B.swift"))

        await #expect(throws: PlanError.missingFile(file: "Sources/B.swift")) {
            _ = try await PlanMaterializer().materialize(plan: plan, projectPath: dir.path, execution: Self.execution)
        }
    }

    @Test("Given a file that is there but is not text, when materialized, then the plan calls it unreadable")
    func aFileThatCannotBeReadIsUnreadable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let plan = try await Planner().plan(input: Self.discoveryInput(for: dir)).plan
        try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: dir.appendingPathComponent("Sources/B.swift"))

        let error = await #expect(throws: PlanError.self) {
            _ = try await PlanMaterializer().materialize(plan: plan, projectPath: dir.path, execution: Self.execution)
        }

        guard case .unreadableFile(let file, _) = error else {
            Issue.record("expected unreadableFile, got \(String(describing: error))")
            return
        }
        #expect(file == "Sources/B.swift")
        #expect(error?.errorDescription?.hasPrefix("plan file Sources/B.swift is there but could not be read") == true)
    }

    @Test("Given a mutant whose text is not at its position, when materialized, then the plan is corrupt")
    func aMutantOffItsTextIsCorrupt() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planned = try await Planner().plan(input: Self.discoveryInput(for: dir)).plan
        let shifted = planned.mutants.map { mutant in
            Plan.Mutant(
                fingerprint: mutant.fingerprint, file: mutant.file, utf8Start: mutant.utf8Start + 1,
                utf8End: mutant.utf8End + 1, line: mutant.line, column: mutant.column,
                operatorIdentifier: mutant.operatorIdentifier,
                replacementKind: mutant.replacementKind, original: mutant.original, replacement: mutant.replacement,
                description: mutant.description, schematizable: mutant.schematizable
            )
        }
        let plan = Plan(
            formatVersion: planned.formatVersion, toolVersion: planned.toolVersion, project: planned.project,
            scope: planned.scope, files: planned.files, mutants: shifted
        )

        await #expect(throws: PlanError.corrupt(fingerprint: shifted[0].fingerprint, file: "Sources/A.swift")) {
            _ = try await PlanMaterializer().materialize(plan: plan, projectPath: dir.path, execution: Self.execution)
        }
    }

    @Test("Given a selection of the plan's mutants, when materialized, then only those are in, with their plan ids")
    func aSelectionKeepsThePlanIds() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let plan = try await Planner().plan(input: Self.discoveryInput(for: dir)).plan
        let logical = try #require(plan.mutants.first { $0.operatorIdentifier == "LogicalOperatorReplacement" })

        let input = try await PlanMaterializer().materialize(
            plan: plan, projectPath: dir.path, execution: Self.execution, mutants: [logical]
        )

        #expect(input.mutants.map(\.id) == [MutantID.make(index: 1)])
        #expect(input.mutants.map(\.fingerprint) == [logical.fingerprint])
        #expect(input.schematizedFiles.map { Planner.relative($0.originalPath, to: dir.path) } == ["Sources/B.swift"])
    }

    // MARK: - Fixture

    static let execution = PlanMaterializer.ExecutionOptions(timeout: 30, concurrency: 1, noCache: true)

    @Test("Given a plan whose mutant names a file the plan does not list, when loaded, then that file is missing")
    func aMutantOfAnUnlistedFileIsMissing() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planned = try await Planner().plan(input: Self.discoveryInput(for: dir)).plan
        let stray = try #require(planned.mutants.first)
        let plan = Plan(
            formatVersion: planned.formatVersion, toolVersion: planned.toolVersion, project: planned.project,
            scope: planned.scope, files: planned.files.filter { $0.path != stray.file }, mutants: [stray]
        )

        #expect(throws: PlanError.missingFile(file: stray.file)) {
            try PlanMaterializer().load(plan: plan, projectPath: dir.path)
        }
        #expect(PlanMaterializer.descriptor(of: stray, at: 0, in: plan, projectPath: dir.path).sourceContentHash == "")
    }

    static func writeProject(in dir: URL) throws {
        let sources = dir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "func a() -> Bool { true }\n".write(
            to: sources.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8
        )
        try "import Foundation\nfunc b(_ x: Bool, _ y: Bool) -> Bool { x && y }\nlet flag = false\n".write(
            to: sources.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8
        )
    }

    static func discoveryInput(for dir: URL) -> DiscoveryInput {
        makeDiscoveryInput(
            projectPath: dir.path, sourcesPath: dir.appendingPathComponent("Sources").path,
            operators: ["BooleanLiteralReplacement", "LogicalOperatorReplacement"]
        )
    }
}
