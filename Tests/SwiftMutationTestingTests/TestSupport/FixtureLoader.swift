import Foundation

func loadTestFixture(_ name: String, extension ext: String = "txt") throws -> String {
    let fixturesURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/\(name).\(ext)")
    return try String(contentsOf: fixturesURL, encoding: .utf8)
}
