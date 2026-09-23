import Foundation

enum BuildError: Error, Equatable, LocalizedError {
    case compilationFailed(output: String)
    case timedOut(seconds: Double, output: String)
    case xctestrunNotFound

    var errorDescription: String? {
        switch self {
        case .compilationFailed(let output):
            var message = "Build failed. The schematized source could not be compiled."
            if !output.isEmpty { message = output + "\n" + message }
            return message

        case .timedOut(let seconds, let output):
            var message = "Build did not finish within \(Int(seconds))s. Raise --build-timeout."
            if !output.isEmpty { message = output + "\n" + message }
            return message

        case .xctestrunNotFound:
            return "xctestrun file not found after build."
        }
    }

    static func == (lhs: BuildError, rhs: BuildError) -> Bool {
        switch (lhs, rhs) {
        case (.compilationFailed, .compilationFailed): return true
        case (.timedOut, .timedOut): return true
        case (.xctestrunNotFound, .xctestrunNotFound): return true
        default: return false
        }
    }
}
