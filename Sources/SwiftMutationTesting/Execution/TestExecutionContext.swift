struct TestExecutionContext: Sendable {
    let artifact: BuildArtifact
    let sandbox: Sandbox
    let pool: SimulatorPool
    let configuration: RunnerConfiguration
    var libraries: Set<TestingFramework> = [.xctest, .swiftTesting]
}
