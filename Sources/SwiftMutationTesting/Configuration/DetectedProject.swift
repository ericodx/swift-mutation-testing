struct DetectedProject: Sendable {
    enum Kind: Sendable {
        case xcode(scheme: String?, allSchemes: [String], destination: String)
        case spm(testTargets: [String])
    }

    static let empty = DetectedProject(
        kind: .xcode(scheme: nil, allSchemes: [], destination: "platform=macOS"),
        testTarget: nil,
        testingFramework: .swiftTesting
    )

    let kind: Kind
    let testTarget: String?
    var testingFramework: TestingFramework = .swiftTesting

    var scheme: String? {
        guard case .xcode(let xScheme, _, _) = kind else { return nil }
        return xScheme
    }

    var allSchemes: [String] {
        guard case .xcode(_, let all, _) = kind else { return [] }
        return all
    }

    var destination: String {
        guard case .xcode(_, _, let dest) = kind else { return "platform=macOS" }
        return dest
    }
}
