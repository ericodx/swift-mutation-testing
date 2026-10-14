struct CacheTestSelection: Codable, Sendable, Equatable {
    let scheme: String?
    let destination: String?
    let container: String?
    let testTarget: String?
    let testingFramework: String
    let xcodebuildArguments: [String]?

    init(_ build: RunnerConfiguration.BuildOptions) {
        if case .xcode(let scheme, let destination) = build.projectType {
            self.scheme = scheme
            self.destination = destination
        } else {
            self.scheme = nil
            self.destination = nil
        }
        container = build.xcodeContainer?.path
        testTarget = build.testTarget
        testingFramework = build.testingFramework.rawValue
        xcodebuildArguments = build.xcodebuildArguments.isEmpty ? nil : build.xcodebuildArguments
    }
}
