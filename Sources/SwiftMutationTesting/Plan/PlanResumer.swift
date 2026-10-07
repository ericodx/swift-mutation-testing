import Foundation

struct PlanResumer: Sendable {
    let plan: Plan
    let shard: Shard?

    struct Discovered {
        let input: RunnerInput
        let identity: RunIdentity
        let duration: TimeInterval
        var resumed: [ExecutionResult] = []
        var journal: PlanJournal?
    }

    func discover(configuration: RunnerConfiguration) async throws -> Discovered {
        let start = Date()
        let identity = RunIdentity(planSha256: try PlanStore.sha256(of: plan), shard: shard)
        let journalPath = PlanJournal.path(
            projectPath: configuration.projectPath, planSha256: identity.planSha256, shard: shard
        )
        let selection = shard.map { ShardSelector.mutants(of: plan, in: $0) } ?? plan.mutants
        let journaled = PlanJournal.entries(at: journalPath)
        let remaining = selection.filter { journaled[$0.fingerprint] == nil }

        let input = try await PlanMaterializer().materialize(
            plan: plan, projectPath: configuration.projectPath,
            execution: PlanMaterializer.ExecutionOptions(configuration), mutants: remaining
        )
        return Discovered(
            input: input, identity: identity, duration: Date().timeIntervalSince(start),
            resumed: resumed(from: journaled, in: selection, projectPath: configuration.projectPath),
            journal: PlanJournal(path: journalPath, mutants: input.mutants)
        )
    }

    // MARK: - Private

    private func resumed(
        from journaled: [String: PlanJournal.Entry], in selection: [Plan.Mutant], projectPath: String
    ) -> [ExecutionResult] {
        let selected = Set(selection.map(\.fingerprint))
        let fileHashes = PlanMaterializer.fileHashes(of: plan)
        return plan.mutants.enumerated().compactMap { index, mutant in
            guard let entry = journaled[mutant.fingerprint], selected.contains(mutant.fingerprint) else { return nil }
            return ExecutionResult(
                descriptor: PlanMaterializer.descriptor(
                    of: mutant, at: index, fileHashes: fileHashes, projectPath: projectPath),
                status: entry.status, testDuration: entry.duration, killerTestFile: entry.killerTestFile,
                activated: entry.activated
            )
        }
    }
}
