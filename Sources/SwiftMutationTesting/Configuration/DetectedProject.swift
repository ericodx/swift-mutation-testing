struct DetectedProject: Sendable {

    static let empty = DetectedProject(
        kind: .xcode(scheme: nil, allSchemes: [], destination: "platform=macOS"),
        testTarget: nil,
        testingFramework: .swiftTesting
    )

    let kind: Kind
    let testTarget: String?
    var testingFramework: TestingFramework = .swiftTesting

    enum Kind: Sendable {
        case xcode(scheme: String?, allSchemes: [String], destination: String)
        case spm(testTargets: [String])
    }
}
