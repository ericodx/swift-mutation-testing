struct TestExecutionContext: Sendable {
    let artifact: BuildArtifact
    let sandbox: Sandbox
    let pool: SimulatorPool
    let configuration: RunnerConfiguration
    var bundles: [TestBundle] = []
    var testFilter: String?
    var targetedSuites: [String: TargetedSuite] = [:]
    var coverage: TestCoverage?

    func bundles(declaring suite: TargetedSuite) -> [TestBundle] {
        let own = bundles.filter { $0.name == suite.testTarget }
        return own.isEmpty ? bundles : own
    }
}
