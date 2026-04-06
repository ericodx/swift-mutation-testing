import Foundation

@testable import SwiftMutationTesting

func makeBuildArtifact(in dir: URL) -> BuildArtifact {
    let plistDict: [String: Any] = ["MyTarget": ["EnvironmentVariables": [String: String]()]]
    let data = try! PropertyListSerialization.data(
        fromPropertyList: plistDict, format: .xml, options: 0
    )
    let plist = XCTestRunPlist(data)!
    return BuildArtifact(derivedDataPath: dir.path, xctestrunURL: dir, plist: plist)
}
