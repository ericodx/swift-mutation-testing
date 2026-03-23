struct DetectedProject: Sendable {

    static let empty = DetectedProject(
        scheme: nil, allSchemes: [], testTarget: nil, destination: "platform=macOS"
    )

    let scheme: String?
    let allSchemes: [String]
    let testTarget: String?
    let destination: String
}
