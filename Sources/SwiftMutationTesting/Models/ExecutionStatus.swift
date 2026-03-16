enum ExecutionStatus: Sendable, Codable, Equatable {
    case killed(by: String)
    case killedByCrash
    case survived
    case unviable
    case timeout
    case noCoverage
}
