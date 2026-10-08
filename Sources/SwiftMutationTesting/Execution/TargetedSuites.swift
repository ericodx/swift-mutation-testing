import Foundation

enum TargetedSuites {

    static let suffix = "Tests"
    static let testsDirectory = "Tests"

    static func declared(
        in testFilePaths: [String],
        read: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> [String: TargetedSuite] {
        var suites: [String: TargetedSuite] = [:]

        for path in testFilePaths {
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

            guard
                name.hasSuffix(suffix),
                let content = read(path),
                declares(name, in: content)
            else { continue }

            suites[name] = TargetedSuite(name: name, testTarget: testTarget(of: path))
        }

        return suites
    }

    static func suite(for sourcePath: String, among suites: [String: TargetedSuite]) -> TargetedSuite? {
        suites[URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent + suffix]
    }

    static func testTarget(of testFilePath: String) -> String? {
        let components = URL(fileURLWithPath: testFilePath).pathComponents

        guard let index = components.lastIndex(of: testsDirectory), index + 2 < components.count else { return nil }

        return components[index + 1]
    }

    // MARK: - Private

    private static func declares(_ name: String, in content: String) -> Bool {
        ["struct", "class", "enum", "actor"].contains { content.contains("\($0) \(name)") }
    }
}
