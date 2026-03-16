import Foundation

struct SandboxFactory: Sendable {
    func create(
        projectPath: String,
        schematizedFiles: [SchematizedFile],
        supportFileContent: String
    ) async throws -> Sandbox {
        let sandboxURL = try makeSandboxRoot()
        let projectURL = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath()

        let schematizedPaths = Dictionary(
            uniqueKeysWithValues: schematizedFiles.map {
                (URL(fileURLWithPath: $0.originalPath).resolvingSymlinksInPath().path, $0.schematizedContent)
            }
        )

        try populateDirectory(
            source: projectURL,
            destination: sandboxURL,
            schematizedPaths: schematizedPaths,
            mutatedMapping: nil
        )

        try injectSupportFile(
            content: supportFileContent,
            into: sandboxURL,
            schematizedFiles: schematizedFiles,
            projectURL: projectURL
        )

        return Sandbox(rootURL: sandboxURL)
    }

    func create(
        projectPath: String,
        mutatedFilePath: String,
        mutatedContent: String
    ) async throws -> Sandbox {
        let sandboxURL = try makeSandboxRoot()
        let projectURL = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath()
        let mutatedCanonical = URL(fileURLWithPath: mutatedFilePath).resolvingSymlinksInPath().path

        try populateDirectory(
            source: projectURL,
            destination: sandboxURL,
            schematizedPaths: [:],
            mutatedMapping: (path: mutatedCanonical, content: mutatedContent)
        )

        return Sandbox(rootURL: sandboxURL)
    }

    private func makeSandboxRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func populateDirectory(
        source: URL,
        destination: URL,
        schematizedPaths: [String: String],
        mutatedMapping: (path: String, content: String)?
    ) throws {
        let items = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )

        for item in items {
            let name = item.lastPathComponent
            let dest = destination.appendingPathComponent(name)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values.isDirectory ?? false
            let isSymlink = values.isSymbolicLink ?? false

            if isDirectory && !isSymlink {
                if shouldSkip(directoryName: name) {
                    continue
                }

                if name.hasSuffix(".xcodeproj") {
                    try processXcodeproj(source: item, destination: dest)
                    continue
                }

                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                try populateDirectory(
                    source: item,
                    destination: dest,
                    schematizedPaths: schematizedPaths,
                    mutatedMapping: mutatedMapping
                )
            } else {
                try writeFile(
                    source: item,
                    destination: dest,
                    schematizedPaths: schematizedPaths,
                    mutatedMapping: mutatedMapping
                )
            }
        }
    }

    private func shouldSkip(directoryName: String) -> Bool {
        directoryName == ".build"
            || directoryName == "DerivedData"
            || directoryName.hasPrefix(".xmr-")
    }

    private func processXcodeproj(source: URL, destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let items = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for item in items {
            let name = item.lastPathComponent
            let dest = destination.appendingPathComponent(name)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir && name == "xcuserdata" {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if isDir && name == "xcshareddata" {
                try FileManager.default.copyItem(at: item, to: dest)
            } else {
                try FileManager.default.createSymbolicLink(at: dest, withDestinationURL: item)
            }
        }
    }

    private func writeFile(
        source: URL,
        destination: URL,
        schematizedPaths: [String: String],
        mutatedMapping: (path: String, content: String)?
    ) throws {
        let canonicalPath = source.resolvingSymlinksInPath().path

        if let content = schematizedPaths[canonicalPath] {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            return
        }

        if let mapping = mutatedMapping, canonicalPath == mapping.path {
            try mapping.content.write(to: destination, atomically: true, encoding: .utf8)
            return
        }

        if source.path.contains(".xcworkspace/xcshareddata/") {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }

        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func injectSupportFile(
        content: String,
        into sandboxURL: URL,
        schematizedFiles: [SchematizedFile],
        projectURL: URL
    ) throws {
        let sourcesURL = sandboxURL.appendingPathComponent("Sources")

        if FileManager.default.fileExists(atPath: sourcesURL.path) {
            try content.write(
                to: sourcesURL.appendingPathComponent("__SMTSupport.swift"),
                atomically: true,
                encoding: .utf8
            )
            return
        }

        guard let firstFile = schematizedFiles.first else { return }

        let originalPath = URL(fileURLWithPath: firstFile.originalPath).resolvingSymlinksInPath().path
        let projectPath = projectURL.path

        guard originalPath.hasPrefix(projectPath) else { return }

        let relative = String(originalPath.dropFirst(projectPath.count + 1))
        let sandboxDirURL = sandboxURL.appendingPathComponent(relative).deletingLastPathComponent()

        try content.write(
            to: sandboxDirURL.appendingPathComponent("__SMTSupport.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}
