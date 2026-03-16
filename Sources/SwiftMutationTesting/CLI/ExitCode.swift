enum ExitCode {
    static let success: Int32 = 0
    static let error: Int32 = 1
}

struct UsageError: Error {
    let message: String
}
