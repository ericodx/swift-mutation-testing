struct ExecutionResult: Sendable, Codable {

    init(
        descriptor: MutantDescriptor,
        status: ExecutionStatus,
        testDuration: Double,
        killerTestFile: String? = nil,
        activated: Bool? = nil,
        unconfirmedKiller: String? = nil,
        fromCache: Bool = false
    ) {
        self.descriptor = descriptor
        self.status = status
        self.testDuration = testDuration
        self.killerTestFile = killerTestFile
        self.activated = activated
        self.unconfirmedKiller = unconfirmedKiller
        self.fromCache = fromCache
    }

    let descriptor: MutantDescriptor
    let status: ExecutionStatus
    let testDuration: Double
    let killerTestFile: String?
    let activated: Bool?
    let unconfirmedKiller: String?
    let fromCache: Bool
}
