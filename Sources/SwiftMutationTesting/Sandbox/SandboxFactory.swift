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

        try disableSwiftLintBuildPhases(in: sandboxURL)

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
            try fixEmptySwitchCaseBodies(content).write(to: destination, atomically: true, encoding: .utf8)
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

    private func disableSwiftLintBuildPhases(in sandboxURL: URL) throws {
        guard let xcodeprojURL = findXcodeproj(in: sandboxURL) else { return }

        let pbxprojURL = xcodeprojURL.appendingPathComponent("project.pbxproj")

        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else { return }

        let data = try Data(contentsOf: pbxprojURL.resolvingSymlinksInPath())

        var format = PropertyListSerialization.PropertyListFormat.xml

        guard
            var plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: &format
            ) as? [String: Any]
        else { return }

        guard var objects = plist["objects"] as? [String: Any] else { return }

        var modified = false

        for (key, value) in objects {
            guard var phase = value as? [String: Any],
                let isa = phase["isa"] as? String,
                isa == "PBXShellScriptBuildPhase",
                let script = phase["shellScript"] as? String,
                script.lowercased().contains("swiftlint")
            else { continue }

            phase["shellScript"] = "exit 0\n"
            objects[key] = phase
            modified = true
        }

        guard modified else { return }

        plist["objects"] = objects

        let xmlData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )

        if (try? pbxprojURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            try FileManager.default.removeItem(at: pbxprojURL)
        }

        try xmlData.write(to: pbxprojURL, options: .atomic)
    }

    private func findXcodeproj(in directory: URL) -> URL? {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []

        return items.first { $0.pathExtension == "xcodeproj" }
    }

    private func fixEmptySwitchCaseBodies(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []

        for idx in 0 ..< lines.count {
            result.append(lines[idx])

            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)

            guard trimmed.hasPrefix("case \""), trimmed.hasSuffix(":") else { continue }

            var nextIdx = idx + 1
            while nextIdx < lines.count, lines[nextIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                nextIdx += 1
            }

            guard nextIdx < lines.count else { continue }

            let next = lines[nextIdx].trimmingCharacters(in: .whitespaces)
            guard next.hasPrefix("case ") || next.hasPrefix("default") || next == "}" else { continue }

            let indent = String(lines[idx].prefix { $0 == " " || $0 == "\t" })
            result.append(indent + "    break")
        }

        return result.joined(separator: "\n")
    }

    private func injectSupportFile(
        content: String,
        into sandboxURL: URL,
        schematizedFiles: [SchematizedFile],
        projectURL: URL
    ) throws {
        guard !content.isEmpty else { return }

        let computedForm =
            "var __swiftMutationTestingID: String {\n"
            + "    ProcessInfo.processInfo.environment[\"__SWIFT_MUTATION_TESTING_ACTIVE\"] ?? \"\"\n"
            + "}"
        let storedForm =
            "nonisolated(unsafe) var __swiftMutationTestingID: String"
            + " = ProcessInfo.processInfo.environment[\"__SWIFT_MUTATION_TESTING_ACTIVE\"] ?? \"\""
        let content = content.replacingOccurrences(of: computedForm, with: storedForm)

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
        let sandboxFileURL = sandboxURL.appendingPathComponent(relative)
        let resolvedURL = sandboxFileURL.resolvingSymlinksInPath()
        let existing = (try? String(contentsOf: resolvedURL, encoding: .utf8)) ?? ""

        try (existing + "\n" + content).write(to: sandboxFileURL, atomically: true, encoding: .utf8)
    }
}
