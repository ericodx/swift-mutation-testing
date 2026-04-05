import Foundation

enum SimulatorError: Error, LocalizedError {
    case deviceNotFound(destination: String)
    case bootTimeout(udid: String)
    case cloneFailed(udid: String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let destination):
            return "No simulator found matching destination: \(destination)"

        case .bootTimeout(let udid):
            return "Simulator \(udid) did not boot within the expected time."

        case .cloneFailed(let udid):
            return "Failed to clone simulator \(udid)."
        }
    }
}
