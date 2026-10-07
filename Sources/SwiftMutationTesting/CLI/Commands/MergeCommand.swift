struct MergeCommand: Command {
    let options: ParsedArguments.PlanOptions
    let configuration: RunnerConfiguration

    func execute() async throws -> ExitCode {
        guard let planPath = options.path else {
            throw UsageError(message: "merge needs the plan the results ran: --plan <plan.json>")
        }
        let (plan, configuration) = try configuration.applyingPlan(at: planPath)
        let conclusion = RunConclusion(
            configuration: configuration, baseline: try RunConclusion.loadBaseline(for: configuration))

        let merged = try ResultMerger().merge(
            resultPaths: options.results, plan: plan, projectPath: configuration.projectPath
        )
        let summary = RunnerSummary(results: merged.results, totalDuration: merged.totalDuration)
        StandardOutput.write(
            "  ✓ Merged \(options.results.count) results of \(planPath): \(summary.results.count) mutants"
        )
        return try conclusion.conclude(
            summary, identity: RunIdentity(planSha256: merged.planSha256, shard: nil)
        )
    }
}
