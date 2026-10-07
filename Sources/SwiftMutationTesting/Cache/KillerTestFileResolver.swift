import Foundation

struct KillerTestFileResolver: Sendable {

    init(
        testFilePaths: [String],
        projectPath: String,
        read: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) {
        self.testFilePaths = testFilePaths
        self.projectPath = projectPath

        var functions: [String: String] = [:]
        var titles: [String: String] = [:]
        for path in testFilePaths {
            guard let content = read(path) else { continue }
            for name in Self.declaredFunctions(in: content) where functions[name] == nil {
                functions[name] = path
            }
            for title in Self.testTitles(in: content) where titles[title] == nil {
                titles[title] = path
            }
        }
        fileByFunction = functions
        fileByTitle = titles
    }

    let testFilePaths: [String]

    private let projectPath: String
    private let fileByFunction: [String: String]
    private let fileByTitle: [String: String]

    func resolve(testName: String) -> String? {
        guard let path = resolveXCTestClassName(testName) ?? resolveSwiftTestingFunctionName(testName) else {
            return nil
        }

        return ProjectRelativePath.make(for: path, in: projectPath)
    }

    private func resolveXCTestClassName(_ testName: String) -> String? {
        let className: String
        let components = testName.split(separator: ".")
        guard components.count >= 2 else { return nil }

        if components.count == 3 {
            className = String(components[1])
        } else {
            className = String(components[0])
        }

        let fileName = "\(className).swift"
        return testFilePaths.first { $0.hasSuffix("/\(fileName)") || $0 == fileName }
    }

    private func resolveSwiftTestingFunctionName(_ testName: String) -> String? {
        guard let name = testName.split(separator: "/").last.map(String.init) else { return nil }

        let baseName = name.firstIndex(of: "(").map { String(name[..<$0]) } ?? name
        return fileByFunction[baseName] ?? fileByTitle[name]
    }

    static func declaredFunctions(in content: String) -> [String] {
        content.matches(of: /func\s+([A-Za-z_][A-Za-z0-9_]*)\s*[(<]/).map { String($0.output.1) }
    }

    static func testTitles(in content: String) -> [String] {
        content.matches(of: /@Test\s*\(\s*"((?:[^"\\]|\\.)*)"/).map { String($0.output.1) }
    }
}
