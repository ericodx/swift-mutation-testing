import Foundation

enum ProjectRelativePath {

    static func make(for path: String, in projectPath: String) -> String {
        Resolver(projectPath: projectPath).make(for: path)
    }

    struct Resolver: Sendable {
        init(projectPath: String) {
            root = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().path
        }

        private let root: String

        func make(for path: String) -> String {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path

            guard resolved.hasPrefix(root + "/") else { return path }

            return String(resolved.dropFirst(root.count + 1))
        }
    }
}
