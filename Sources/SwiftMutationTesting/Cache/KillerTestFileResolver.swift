import Foundation

struct KillerTestFileResolver: Sendable {

    init(testFilePaths: [String], projectPath: String) {
        self.testFilePaths = testFilePaths
        self.projectPath = projectPath
    }

    let testFilePaths: [String]

    private let projectPath: String

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
        let components = testName.split(separator: "/")
        guard let lastComponent = components.last else { return nil }

        let functionName = String(lastComponent)

        for path in testFilePaths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            if content.contains("func \(functionName)")
                || content.contains("@Test") && content.contains(functionName)
            {
                return path
            }
        }

        return nil
    }
}
