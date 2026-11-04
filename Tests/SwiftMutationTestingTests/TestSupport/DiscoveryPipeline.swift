@testable import SwiftMutationTesting

struct DiscoveryPipeline: Sendable {
    func run(input: DiscoveryInput) async throws -> RunnerInput {
        let planned = try await Planner().plan(input: input)
        return try PlanMaterializer().materialize(
            plan: planned.plan,
            projectPath: input.projectPath,
            sources: planned.sources,
            execution: .init(timeout: input.timeout, concurrency: input.concurrency, noCache: input.noCache)
        )
    }
}
