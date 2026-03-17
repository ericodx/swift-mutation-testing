enum RunnerEvent: Sendable {
    case buildStarted
    case buildFinished(duration: Double)
    case simulatorPoolReady(size: Int)

    case mutantStarted(descriptor: MutantDescriptor, index: Int, total: Int)
    case mutantFinished(descriptor: MutantDescriptor, status: ExecutionStatus, index: Int, total: Int)

    case fallbackBuildStarted(filePath: String)
    case fallbackBuildFinished(filePath: String, success: Bool)
}
