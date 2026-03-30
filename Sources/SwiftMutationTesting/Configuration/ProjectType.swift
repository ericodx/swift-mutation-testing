enum ProjectType: Sendable, Equatable {
    case xcode(scheme: String, destination: String)
    case spm
}
