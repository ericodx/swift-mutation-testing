struct ExecutionResult: Sendable, Codable {

    init(descriptor: MutantDescriptor, status: ExecutionStatus, testDuration: Double, killerTestFile: String? = nil) {
        self.descriptor = descriptor
        self.status = status
        self.testDuration = testDuration
        self.killerTestFile = killerTestFile
    }

    let descriptor: MutantDescriptor
    let status: ExecutionStatus
    let testDuration: Double
    let killerTestFile: String?
}
