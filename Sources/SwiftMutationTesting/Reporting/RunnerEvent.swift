enum RunnerEvent: Sendable {
    case discoveryFinished(mutantCount: Int, schematizableCount: Int, incompatibleCount: Int, duration: Double)
    case loadedFromCache(mutantCount: Int)

    case schemaBatchStarted(index: Int, count: Int, limit: Int)
    case buildStarted
    case buildFinished(duration: Double)
    case schemaNarrowed(excludedCount: Int)
    case schemaSuiteFailed(splitting: Bool)
    case workersReady(count: Int, usesSimulators: Bool)

    case mutantStarted(descriptor: MutantDescriptor, index: Int, total: Int)
    case mutantFinished(descriptor: MutantDescriptor, status: ExecutionStatus, index: Int, total: Int)

    case fallbackBuildStarted(filePath: String)
    case fallbackBuildFinished(filePath: String, success: Bool)
}
