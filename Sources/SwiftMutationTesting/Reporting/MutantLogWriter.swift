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
        output: String,
        activated: Bool? = nil
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let header = header(mutant: mutant, status: status, duration: duration, activated: activated)
        let contents = header + "\n" + output

        try? contents.write(
            to: directory.appendingPathComponent("\(mutant.id).log"),
            atomically: true,
            encoding: .utf8
        )
    }

    func write(baselineOutput output: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? output.write(to: directory.appendingPathComponent("baseline.log"), atomically: true, encoding: .utf8)
    }

    static let timingFileName = "timing.json"

    func write(timing: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? timing.write(to: directory.appendingPathComponent(Self.timingFileName), options: .atomic)
    }

    // MARK: - Private

    private func header(
        mutant: MutantDescriptor,
        status: ExecutionStatus,
        duration: Double,
        activated: Bool?
    ) -> String {
        """
        mutant:    \(mutant.id)
        location:  \(mutant.filePath):\(mutant.line):\(mutant.column)
        operator:  \(mutant.operatorIdentifier)
        mutation:  \(mutant.originalText) → \(mutant.mutatedText)
        status:    \(statusLine(status))
        activated: \(activationLine(activated))
        duration:  \(String(format: "%.2f", duration))s
        ---
        """
    }

    private func activationLine(_ activated: Bool?) -> String {
        switch activated {
        case .some(true): "yes, the mutated code ran"
        case .some(false): "no, the mutated code never ran"
        case .none: "not measured"
        }
    }

    private func statusLine(_ status: ExecutionStatus) -> String {
        switch status {
        case .killed(let test): "Killed by \(test)"
        case .killedByCrash: "Crash"
        case .survived: "Survived"
        case .unviable: "Unviable"
        case .timeout: "Timeout"
        case .noCoverage: "NoCoverage"
        }
    }
}
