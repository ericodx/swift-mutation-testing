import Foundation

enum ProjectRelativePath {

    static func make(for path: String, in projectPath: String) -> String {
        let root = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path

        guard resolved.hasPrefix(root + "/") else { return path }

        return String(resolved.dropFirst(root.count + 1))
    }
}
