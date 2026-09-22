import Foundation

/// Writes what a mutant's tests printed to a file, one per mutant.
///
/// The output is otherwise parsed into a verdict and dropped, which leaves an unexpected verdict
/// with nothing behind it to read. `.killedByCrash` in particular is reachable three separate ways
/// in `TestOutputParser` — a fatal error, a bad instruction, or test output naming no failing test
/// — and the verdict alone does not say which (issue #75).
///
/// Failing to write a log never fails a run: the logs exist to explain a result, and losing the
/// explanation is not a reason to lose the result.
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

    /// Enough about the mutant to read a log on its own, without cross-referencing the report.
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
