struct IncompatibleTestLaunchResult: Sendable {
    let exitCode: Int32
    let output: String
    let xcresultPath: String
    let duration: Double
}
