import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SwiftMutationTesting plan and run --plan", .serialized)
struct SwiftMutationTestingPlanTests {
    @Test("Given the plan command, when run, then the plan is written and the console says so")
    func planWritesThePlan() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path

        var result: ExitCode = .error
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath])
        }

        #expect(result == .success)
        #expect(output.contains("Plan: \(planPath) (2 mutants in 1 files)"))
        let plan = try PlanStore().read(from: planPath)
        #expect(plan.mutants.count == 2)
        #expect(plan.scope.operators == OperatorRegistry.operatorNames(upTo: .standard))
        #expect(plan.project.type == "spm")
    }

    @Test("Given a plan whose file changed, when run --plan, then the run refuses with the file's name")
    func aStalePlanRefusesToRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a || b }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
        )

        let result = await SwiftMutationTesting.run(
            args: ["run", dir.path, "--plan", planPath, "--quiet"], launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .error)
        let plan = try PlanStore().read(from: planPath)
        #expect(throws: PlanError.stale(file: "Foo.swift")) {
            try PlanMaterializer().load(plan: plan, projectPath: dir.path)
        }
    }

    @Test("Given a plan, when run --plan with a shard, then only that shard's mutants run and the report says which")
    func aShardRunsItsMutantsAndNamesItself() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        try "func g(_ a: Bool, _ b: Bool) -> Bool { a || b }\n".write(
            to: dir.appendingPathComponent("Bar.swift"), atomically: true, encoding: .utf8
        )
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let plan = try PlanStore().read(from: planPath)
        let reportPath = dir.appendingPathComponent("r.json").path

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        let result = await SwiftMutationTesting.run(
            args: [
                "run", dir.path, "--plan", planPath, "--shard", "2/2", "--quiet", "--output", reportPath, "--no-cache",
            ],
            launcher: launcher
        )

        #expect(result == .success)
        let tested = await launcher.requests.compactMap { $0.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] }
            .filter { !$0.isEmpty }
        let expected = ShardSelector.mutants(of: plan, in: Shard(index: 2, count: 2))
        #expect(!expected.isEmpty)
        #expect(Set(tested) == Set(expected.map { MutantID.make(index: plan.mutants.firstIndex(of: $0)!) }))

        let data = try Data(contentsOf: URL(fileURLWithPath: reportPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let config = json?["config"] as? [String: Any]
        #expect(config?["planSha256"] as? String == (try PlanStore.sha256(of: plan)))
        #expect(config?["shard"] as? String == "2/2")
    }

    @Test("Given a plain run, when reported, then the report carries the hash of the plan it made")
    func aPlainRunHasAPlanToo() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let reportPath = dir.appendingPathComponent("r.json").path
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])

        let result = await SwiftMutationTesting.run(
            args: ["run", dir.path, "--quiet", "--output", reportPath, "--no-cache"],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .success)
        let data = try Data(contentsOf: URL(fileURLWithPath: reportPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let config = json?["config"] as? [String: Any]
        #expect(config?["planSha256"] as? String == (try PlanStore.sha256(of: PlanStore().read(from: planPath))))
        #expect(config?["shard"] == nil)
    }

    @Test("Given a plan run in two shards, when merged, then the report is the single run's, mutant by mutant")
    func shardsMergeIntoTheSingleRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        try "func g(_ a: Bool, _ b: Bool) -> Bool { a || b }\n".write(
            to: dir.appendingPathComponent("Bar.swift"), atomically: true, encoding: .utf8
        )
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let paths = ["single", "one", "two", "merged"].map { dir.appendingPathComponent("\($0).json").path }

        for (arguments, path) in [([], paths[0]), (["--shard", "1/2"], paths[1]), (["--shard", "2/2"], paths[2])] {
            let result = await SwiftMutationTesting.run(
                args: ["run", dir.path, "--plan", planPath, "--quiet", "--no-cache", "--output", path] + arguments,
                launcher: MockProcessLauncher(exitCode: 1)
            )
            #expect(result == .success)
        }
        let merged = await captureOutput {
            _ = await SwiftMutationTesting.run(
                args: ["merge", paths[1], paths[2], "--plan", planPath, "--output", paths[3], "--quiet"]
            )
        }

        #expect(merged.contains("Merged 2 results"))
        let single = try Self.verdicts(at: paths[0])
        #expect(try Self.verdicts(at: paths[3]) == single)
        #expect(single.count == 3)
    }

    @Test("Given a merge with a shard missing, when run, then it fails and writes no report")
    func aMissingShardFailsTheMerge() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        try "func g(_ a: Bool, _ b: Bool) -> Bool { a || b }\n".write(
            to: dir.appendingPathComponent("Bar.swift"), atomically: true, encoding: .utf8
        )
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let one = dir.appendingPathComponent("one.json").path
        _ = await SwiftMutationTesting.run(
            args: ["run", dir.path, "--plan", planPath, "--shard", "1/2", "--quiet", "--no-cache", "--output", one],
            launcher: MockProcessLauncher(exitCode: 1)
        )
        let mergedPath = dir.appendingPathComponent("merged.json").path

        let result = await SwiftMutationTesting.run(args: ["merge", one, "--plan", planPath, "--output", mergedPath])

        #expect(result == .error)
        #expect(!FileManager.default.fileExists(atPath: mergedPath))
    }

    @Test("Given the reproduce command without a plan, when run, then the plan is made in memory and the mutant runs")
    func reproduceWithoutAPlan() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)

        var result: ExitCode = .error
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(
                args: ["reproduce", "swift-mutation-testing_0", dir.path], launcher: MockProcessLauncher(exitCode: 1)
            )
        }
        let sandboxes = output.split(separator: "\n").filter { $0.hasPrefix("Sandbox: ") }.map {
            String($0.dropFirst(9))
        }
        defer { for sandbox in sandboxes { try? FileManager.default.removeItem(atPath: sandbox) } }

        #expect(result == .success)
        #expect(output.contains("Reproducing swift-mutation-testing_0"))
        #expect(output.contains("Verdict: "))
    }

    @Test("Given the reproduce command with a plan, when run, then the mutant is taken from that plan")
    func reproduceWithAPlan() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])

        var result: ExitCode = .error
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(
                args: ["reproduce", "swift-mutation-testing_0", dir.path, "--plan", planPath],
                launcher: MockProcessLauncher(exitCode: 1)
            )
        }
        let sandboxes = output.split(separator: "\n").filter { $0.hasPrefix("Sandbox: ") }.map {
            String($0.dropFirst(9))
        }
        defer { for sandbox in sandboxes { try? FileManager.default.removeItem(atPath: sandbox) } }

        #expect(result == .success)
        #expect(output.contains("Reproducing swift-mutation-testing_0"))
    }

    @Test("Given the merge command without a plan, when run, then it fails before reading any result")
    func mergeNeedsThePlan() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)

        let result = await SwiftMutationTesting.run(
            args: ["merge", dir.appendingPathComponent("one.json").path, "--project-path", dir.path]
        )

        #expect(result == .error)
    }

    @Test("Given the reproduce command with an unknown mutant, when run, then it fails")
    func reproduceAnUnknownMutant() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)

        let result = await SwiftMutationTesting.run(
            args: ["reproduce", "swift-mutation-testing_99", dir.path], launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .error)
    }

    @Test("Given a plan run that was interrupted, when run again, then only the mutants without a verdict run")
    func anInterruptedPlanRunResumes() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let plan = try PlanStore().read(from: planPath)
        let journalPath = PlanJournal.path(
            projectPath: dir.path, planSha256: try PlanStore.sha256(of: plan), shard: nil
        )
        let first = PlanMaterializer.descriptor(of: plan.mutants[0], at: 0, in: plan, projectPath: dir.path)
        PlanJournal(path: journalPath, mutants: [first]).record(
            status: .killed(by: "Earlier.test"), for: MutantCacheKey.make(for: first), killerTestFile: nil,
            activated: true, duration: 1
        )
        let reportPath = dir.appendingPathComponent("r.json").path

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        var result: ExitCode = .error
        let output = await captureOutput {
            result = await SwiftMutationTesting.run(
                args: ["run", dir.path, "--plan", planPath, "--no-cache", "--output", reportPath],
                launcher: launcher
            )
        }

        #expect(result == .success)
        #expect(output.contains("Resumed 1 verdicts from an interrupted run of this plan"))
        let tested = await launcher.requests.compactMap { $0.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] }
            .filter { !$0.isEmpty }
        #expect(Set(tested) == Set((1 ..< plan.mutants.count).map(MutantID.make(index:))))
        let report = try Self.verdicts(at: reportPath)
        #expect(report.count == plan.mutants.count)
        #expect(report[plan.mutants[0].fingerprint] == "Killed")
        #expect(!FileManager.default.fileExists(atPath: journalPath))
    }

    @Test("Given an interrupted run whose every mutant has a verdict, when run again, then nothing is built")
    func aFullyJournaledRunBuildsNothing() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let plan = try PlanStore().read(from: planPath)
        let journalPath = PlanJournal.path(
            projectPath: dir.path, planSha256: try PlanStore.sha256(of: plan), shard: nil)
        let descriptors = plan.mutants.enumerated().map {
            PlanMaterializer.descriptor(of: $0.element, at: $0.offset, in: plan, projectPath: dir.path)
        }
        let journal = PlanJournal(path: journalPath, mutants: descriptors)
        for descriptor in descriptors {
            journal.record(
                status: .survived, for: MutantCacheKey.make(for: descriptor), killerTestFile: nil, activated: true,
                duration: 1
            )
        }

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        let result = await SwiftMutationTesting.run(
            args: ["run", dir.path, "--plan", planPath, "--no-cache", "--quiet"], launcher: launcher
        )

        #expect(result == .success)
        #expect(await launcher.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: journalPath))
    }

    @Test("Given a finished plan run, when run again, then every mutant runs: the journal only resumes interruptions")
    func aFinishedRunLeavesNoJournal() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let plan = try PlanStore().read(from: planPath)
        _ = await SwiftMutationTesting.run(
            args: ["run", dir.path, "--plan", planPath, "--no-cache", "--quiet"],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        let launcher = RecordingProcessLauncher(responses: [(0, "")])
        _ = await SwiftMutationTesting.run(
            args: ["run", dir.path, "--plan", planPath, "--no-cache", "--quiet"], launcher: launcher
        )

        let tested = await launcher.requests.compactMap { $0.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] }
            .filter { !$0.isEmpty }
        #expect(Set(tested).count == plan.mutants.count)
    }

    static func verdicts(at path: String) throws -> [String: String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let payload = try JSONDecoder().decode(MutationReportPayload.self, from: data)
        return Dictionary(
            uniqueKeysWithValues: payload.files.values.flatMap(\.mutants).map { ($0.fingerprint, $0.status) })
    }

    @Test("Given reproduce with no mutant and no launcher, when run, then the empty reference is refused")
    func aReproductionWithoutAMutantIsRefused() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try Self.writeProject(in: dir)
        let planPath = dir.appendingPathComponent("plan.json").path
        _ = await SwiftMutationTesting.run(args: ["plan", dir.path, "--output", planPath, "--quiet"])
        let configuration = try ConfigurationResolver().resolve(
            cliArguments: ParsedArguments(projectPath: dir.path), fileValues: [:]
        )
        let command = ReproduceCommand(
            options: ParsedArguments.PlanOptions(path: planPath), configuration: configuration, launcher: nil
        )

        await #expect(throws: PlanError.unknownMutant("")) {
            _ = try await command.execute()
        }
    }

    static func writeProject(in dir: URL) throws {
        try "func f(_ a: Bool, _ b: Bool) -> Bool { a && b }\nfunc h(_ x: Int) -> Bool { x > 0 ? true : false }\n"
            .write(
                to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8
            )
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"P\")\n".write(
            to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
    }
}
