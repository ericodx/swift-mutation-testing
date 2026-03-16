import Foundation

struct BuildArtifact: Sendable {
    let derivedDataPath: String
    let xctestrunURL: URL
    let plist: XCTestRunPlist
}
