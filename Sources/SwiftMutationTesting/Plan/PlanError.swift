import Foundation

enum PlanError: Error, Equatable, LocalizedError {
    case notFound(path: String)
    case unreadable(path: String)
    case unsupportedVersion(path: String, version: Int)
    case unknownProjectType(String)
    case stale(file: String)
    case missingFile(file: String)
    case unreadableFile(file: String, reason: String)
    case corrupt(fingerprint: String, file: String)
    case invalidShard(String)
    case unknownMutant(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "plan '\(path)' does not exist; write one with `swift-mutation-testing plan --output \(path)`"

        case .unreadable(let path):
            return "plan '\(path)' could not be read as a swift-mutation-testing plan"

        case .unsupportedVersion(let path, let version):
            return "plan '\(path)' has format version \(version), which this version cannot read; make it again"

        case .unknownProjectType(let type):
            return "plan names a project type this version does not know: '\(type)'"

        case .stale(let file):
            return "plan is stale: \(file) changed since the plan was made; make the plan again"

        case .missingFile(let file):
            return "plan is stale: \(file) is no longer there; make the plan again"

        case .unreadableFile(let file, let reason):
            return "plan file \(file) is there but could not be read: \(reason)"

        case .corrupt(let fingerprint, let file):
            return "plan is corrupt: mutant \(fingerprint) does not match the text at its position in \(file)"

        case .invalidShard(let raw):
            return "--shard must be i/n with 1 ≤ i ≤ n, not '\(raw)'"

        case .unknownMutant(let reference):
            return "no mutant '\(reference)' in the plan; give a fingerprint or an id such as "
                + MutantID.make(index: 12)
        }
    }
}
