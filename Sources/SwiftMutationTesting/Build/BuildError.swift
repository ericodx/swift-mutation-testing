enum BuildError: Error, Equatable {
    case compilationFailed(output: String)
    case xctestrunNotFound

    static func == (lhs: BuildError, rhs: BuildError) -> Bool {
        switch (lhs, rhs) {
        case (.compilationFailed, .compilationFailed): return true
        case (.xctestrunNotFound, .xctestrunNotFound): return true
        default: return false
        }
    }
}
