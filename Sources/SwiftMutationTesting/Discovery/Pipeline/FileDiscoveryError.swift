enum FileDiscoveryError: Error, Equatable, Sendable {
    case sourcesPathNotFound(String)
}
