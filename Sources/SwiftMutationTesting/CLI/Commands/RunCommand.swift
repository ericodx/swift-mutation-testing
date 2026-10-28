import Foundation

struct RunCommand: Command {
    let configuration: RunnerConfiguration
    let planPath: String?
    let shard: Shard?
    let launcher: (any ProcessLaunching)?

    func execute() async throws -> ExitCode {
        var configuration = configuration
        var planned: PlanResumer?
        if let planPath {
            let plan: Plan
            (plan, configuration) = try configuration.applyingPlan(at: planPath)
            planned = PlanResumer(plan: plan, shard: shard)
        }

        let conclusion = RunConclusion(
            configuration: configuration, baseline: try RunConclusion.loadBaseline(for: configuration)
        )

        return try await SleepInhibitor.preventingIdleSleep { [configuration, planned] in
            try await run(configuration: configuration, planned: planned, conclusion: conclusion)
        }
    }

    // MARK: - Private

    private func run(
        configuration: RunnerConfiguration, planned: PlanResumer?, conclusion: RunConclusion
    ) async throws -> ExitCode {
        let discovered = try await discover(configuration: configuration, planned: planned)
        let input = discovered.input

        if input.mutants.isEmpty, discovered.resumed.isEmpty, planned?.shard == nil {
            throw FileDiscoveryError.noMutants(for: configuration)
        }

        await ConsoleProgressReporter.announceDiscovery(
            mutantCount: input.mutants.count,
            schematizableCount: input.mutants.filter(\.isSchematizable).count,
            duration: discovered.duration,
            unless: configuration.reporting.quiet
        )

        let executionLauncher = launcher ?? configuration.build.projectType.defaultLauncher

        SandboxCleaner.clearLeftovers()

        if !discovered.resumed.isEmpty, !configuration.reporting.quiet {
            StandardOutput.write(
                "  ✓ Resumed \(discovered.resumed.count) verdicts from an interrupted run of this plan"
            )
        }

        let timings = PhaseTimings()
        await timings.record(.discovery, start: Date(timeIntervalSinceNow: -discovered.duration))

        let start = Date()
        var results = discovered.resumed
        if !input.mutants.isEmpty || discovered.resumed.isEmpty {
            results += try await MutantExecutor(
                configuration: configuration, launcher: executionLauncher, planJournal: discovered.journal,
                environment: MutantExecutor.Environment(timings: timings)
            ).execute(input)
        }
        results = MutantID.ordered(results, by: \.descriptor.id)
        if let journal = discovered.journal {
            PlanJournal.remove(at: journal.path)
        }

        let summary = RunnerSummary(
            results: results, totalDuration: Date().timeIntervalSince(start), phases: await timings.entries
        )
        return try conclusion.conclude(summary, identity: discovered.identity)
    }

    private func discover(
        configuration: RunnerConfiguration, planned: PlanResumer?
    ) async throws -> PlanResumer.Discovered {
        if let planned {
            return try await planned.discover(configuration: configuration)
        }

        let start = Date()
        let made = try await Planner().plan(for: configuration)
        let input = try PlanMaterializer().materialize(
            plan: made.plan, projectPath: configuration.projectPath, sources: made.sources,
            execution: PlanMaterializer.ExecutionOptions(configuration)
        )
        let identity = RunIdentity(planSha256: try PlanStore.sha256(of: made.plan), shard: nil)
        return PlanResumer.Discovered(input: input, identity: identity, duration: Date().timeIntervalSince(start))
    }
}
