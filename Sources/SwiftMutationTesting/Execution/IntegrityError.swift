import Foundation

enum IntegrityError: Error, Equatable, LocalizedError {
    case mutantsNotApplied(mutants: [String])
    case schemaNotApplied(path: String)
    case supportMissing(path: String)
    case activationNeverObserved(killed: Int)
    case sourceNotRestored(path: String)

    var errorDescription: String? {
        switch self {
        case .activationNeverObserved(let killed):
            let count = "\(killed) mutant\(killed == 1 ? " was" : "s were")"
            return "\(count) killed, but no mutant's code was ever seen running. "
                + "Either the activation marker cannot be written in this environment or the suite fails on its own, "
                + "so every verdict is suspect. The run is stopped"

        case .mutantsNotApplied(let mutants):
            let listed = mutants.prefix(10).joined(separator: ", ")
            let more = mutants.count > 10 ? " and \(mutants.count - 10) more" : ""
            let count = "\(mutants.count) mutant\(mutants.count == 1 ? " was" : "s were")"
            return "\(count) not applied to the sandbox: \(listed)\(more). "
                + "The run is stopped, since a verdict on a mutation that is not in the build says nothing"

        case .schemaNotApplied(let path):
            return "the sandbox copy of '\(path)' is identical to the original, "
                + "so none of its mutants is in the build. The run is stopped"

        case .sourceNotRestored(let path):
            return "the sandbox copy of '\(path)' could not be linked back to the original after its mutant ran, "
                + "so every later mutant built in that sandbox would be judged without the file. The run is stopped"

        case .supportMissing(let path):
            return "the sandbox copy of '\(path)' does not declare \(SupportDeclarations.identifier(for: path)), "
                + "so its schema could not compile. The run is stopped"
        }
    }
}
