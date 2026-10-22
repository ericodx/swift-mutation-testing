struct TestLaunchResult: Sendable {
    let exitCode: Int32
    let output: String
    let xcresultPath: String
    let duration: Double
    var activated: Bool = false
    var settledByTargetedSuite: Bool = false
}
