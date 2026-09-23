import Foundation

struct MutantLogWriter: Sendable {

    init?(directory: String?) {
        guard let directory else { return nil }
        self.directory = URL(fileURLWithPath: directory)
    }

    private let directory: URL

    func write(
        mutant: MutantDescriptor,
        status: ExecutionStatus,
        duration: Double,
        output: String
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let contents = header(mutant: mutant, status: status, duration: duration) + "\n" + output

        try? contents.write(
            to: directory.appendingPathComponent("\(mutant.id).log"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Private

    private func header(mutant: MutantDescriptor, status: ExecutionStatus, duration: Double) -> String {
        """
        mutant:   \(mutant.id)
        location: \(mutant.filePath):\(mutant.line):\(mutant.column)
        operator: \(mutant.operatorIdentifier)
        mutation: \(mutant.originalText) → \(mutant.mutatedText)
        status:   \(statusLine(status))
        duration: \(String(format: "%.2f", duration))s
        ---
        """
    }

    private func statusLine(_ status: ExecutionStatus) -> String {
        guard case .killed(let test) = status else { return status.mutationReportStatus }
        return "\(status.mutationReportStatus) by \(test)"
    }
}
