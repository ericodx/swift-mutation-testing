import Foundation

enum SimulatorError: Error, LocalizedError {
    case deviceNotFound(destination: String)
    case bootTimeout(udid: String)
    case cloneFailed(udid: String, dataSize: Int64? = nil)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let destination):
            return "No simulator found matching destination: \(destination)"

        case .bootTimeout(let udid):
            return "Simulator \(udid) did not boot within the expected time."

        case .cloneFailed(let udid, let dataSize):
            guard let dataSize else { return "Failed to clone simulator \(udid)." }
            return
                "Failed to clone simulator \(udid). Its data holds \(Self.gigabytes(dataSize)), "
                + "which every clone copies: `xcrun simctl erase \(udid)` or a dedicated device clones faster."
        }
    }

    static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
