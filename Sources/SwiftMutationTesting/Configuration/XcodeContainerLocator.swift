import Foundation

enum XcodeContainerLocator {
    struct Candidates: Sendable, Equatable {
        let workspaces: [String]
        let projects: [String]
    }

    static func locate(
        in root: URL, workspace: String?, project: String?, fileSystem: FileSystem = FileSystem()
    ) throws(UsageError) -> XcodeContainer? {
        if workspace != nil, project != nil {
            throw UsageError(message: "--workspace and --project cannot be used together; give one container")
        }

        if let workspace {
            let relative = try existing(
                workspace, extension: "xcworkspace", flag: "--workspace", in: root, fileSystem: fileSystem
            )
            try requireReferencesInside(root, workspace: relative)
            return .workspace(relative)
        }

        if let project {
            return .project(
                try existing(project, extension: "xcodeproj", flag: "--project", in: root, fileSystem: fileSystem)
            )
        }

        let found = candidates(in: root, fileSystem: fileSystem)
        switch (found.workspaces.count, found.projects.count) {
        case (1, _):
            try requireReferencesInside(root, workspace: found.workspaces[0])
            return .workspace(found.workspaces[0])

        case (0, 1):
            return .project(found.projects[0])

        case (0, 0):
            let nested = nestedCandidates(in: root, fileSystem: fileSystem)
            guard nested.workspaces.isEmpty, nested.projects.isEmpty else {
                throw UsageError(
                    message: "no .xcworkspace or .xcodeproj at the project root, but found "
                        + "\(list(nested.workspaces + nested.projects)) below it; pass --workspace or --project "
                        + "(or the `workspace` / `project` key) with the one to build"
                )
            }
            return nil

        default:
            let names = found.workspaces.count > 1 ? found.workspaces : found.projects
            let flag = found.workspaces.count > 1 ? "--workspace" : "--project"
            throw UsageError(
                message: "found \(list(names)) at the project root; pass \(flag) (or the `\(flag.dropFirst(2))` key)"
                    + " to choose one"
            )
        }
    }

    static func candidates(in root: URL, fileSystem: FileSystem = FileSystem()) -> Candidates {
        let names = fileSystem.contentsOfDirectory(root.path).sorted()
        return Candidates(
            workspaces: names.filter { $0.hasSuffix(".xcworkspace") },
            projects: names.filter { $0.hasSuffix(".xcodeproj") }
        )
    }

    static func nestedCandidates(in root: URL, depth: Int = 3, fileSystem: FileSystem = FileSystem()) -> Candidates {
        let skipped: Set<String> = ["DerivedData", "Pods", "Carthage", "node_modules", "Build"]
        var workspaces: [String] = []
        var projects: [String] = []
        var level = [root]
        for _ in 0 ..< depth {
            var next: [URL] = []
            for directory in level {
                let names = fileSystem.contentsOfDirectory(directory.path)
                for name in names where !name.hasPrefix(".") && !skipped.contains(name) {
                    let url = directory.appendingPathComponent(name)
                    guard fileSystem.directoryExists(url.path) else { continue }
                    if name.hasSuffix(".xcworkspace"), directory != root {
                        workspaces.append(String(url.path.dropFirst(root.path.count + 1)))
                    } else if name.hasSuffix(".xcodeproj"), directory != root {
                        projects.append(String(url.path.dropFirst(root.path.count + 1)))
                    } else if !name.hasSuffix(".xcworkspace"), !name.hasSuffix(".xcodeproj") {
                        next.append(url)
                    }
                }
            }
            level = next
        }
        return Candidates(workspaces: workspaces.sorted(), projects: projects.sorted())
    }

    static func projects(referencedBy workspace: String, in root: URL) -> [String] {
        references(of: workspace, in: root)
            .filter { $0.hasSuffix(".xcodeproj") }
            .map { relative($0, to: root) ?? $0 }
    }

    // MARK: - Private

    private static func existing(
        _ path: String, extension ext: String, flag: String, in root: URL, fileSystem: FileSystem
    ) throws(UsageError) -> String {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        guard url.pathExtension == ext, fileSystem.directoryExists(url.path) else {
            throw UsageError(message: "\(flag) '\(path)' is not a .\(ext) under \(root.path)")
        }
        guard let relative = relative(url.path, to: root) else {
            throw UsageError(message: "\(flag) '\(path)' is outside the project root \(root.path)")
        }
        return relative
    }

    private static func requireReferencesInside(_ root: URL, workspace: String) throws(UsageError) {
        let outside = references(of: workspace, in: root).filter { relative($0, to: root) == nil }
        guard outside.isEmpty else {
            throw UsageError(
                message: "\(workspace) references \(list(outside)) outside the project root; the sandbox only holds "
                    + "the root, so run from a directory that contains every project of the workspace"
            )
        }
    }

    private static func references(of workspace: String, in root: URL) -> [String] {
        let workspaceURL = root.appendingPathComponent(workspace)
        let contents = workspaceURL.appendingPathComponent("contents.xcworkspacedata")
        guard let parser = XMLParser(contentsOf: contents) else { return [] }
        let collector = ReferenceCollector(container: workspaceURL.deletingLastPathComponent())
        parser.delegate = collector
        parser.parse()
        return collector.references
    }

    private static func relative(_ path: String, to root: URL) -> String? {
        let base = root.standardizedFileURL.path
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        guard target.hasPrefix(base + "/") else { return nil }
        return String(target.dropFirst(base.count + 1))
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.joined() }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    private final class ReferenceCollector: NSObject, XMLParserDelegate {
        private let container: URL
        private var groups: [URL] = []
        private(set) var references: [String] = []

        init(container: URL) {
            self.container = container
        }

        func parser(
            _: XMLParser, didStartElement element: String, namespaceURI _: String?, qualifiedName _: String?,
            attributes: [String: String] = [:]
        ) {
            guard element == "Group" || element == "FileRef" else { return }
            let base = groups.last ?? container
            let location = attributes["location"].flatMap { resolve($0, base: base) }

            if element == "Group" {
                groups.append(location ?? base)
            } else if let location {
                references.append(location.path)
            }
        }

        func parser(
            _: XMLParser, didEndElement element: String, namespaceURI _: String?, qualifiedName _: String?
        ) {
            if element == "Group", !groups.isEmpty {
                groups.removeLast()
            }
        }

        private func resolve(_ location: String, base: URL) -> URL? {
            guard let colon = location.firstIndex(of: ":") else { return nil }
            let kind = location[..<colon]
            let path = String(location[location.index(after: colon)...])
            switch kind {
            case "group": return path.isEmpty ? base : base.appendingPathComponent(path)
            case "container": return path.isEmpty ? container : container.appendingPathComponent(path)
            case "absolute": return URL(fileURLWithPath: path)
            default: return nil
            }
        }
    }
}
