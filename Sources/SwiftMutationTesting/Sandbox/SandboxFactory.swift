import Foundation

struct SandboxFactory: Sendable {
    func create(
        projectPath: String,
        schematizedFiles: [SchematizedFile]
    ) async throws -> Sandbox {
        let schematizedPaths = Dictionary(
            uniqueKeysWithValues: schematizedFiles.map {
                (URL(fileURLWithPath: $0.originalPath).resolvingSymlinksInPath().path, $0.schematizedContent)
            }
        )

        return try await Self.offCooperativePool {
            let sandbox = try populate(projectPath: projectPath, replacing: schematizedPaths)
            try disableSwiftLintBuildPhases(in: sandbox.rootURL)
            return sandbox
        }
    }

    func createClean(projectPath: String, disablingSwiftLint: Bool = false) async throws -> Sandbox {
        try await Self.offCooperativePool {
            let sandbox = try populate(projectPath: projectPath, replacing: [:])
            if disablingSwiftLint {
                try disableSwiftLintBuildPhases(in: sandbox.rootURL)
            }
            return sandbox
        }
    }

    func create(
        projectPath: String,
        mutatedFilePath: String,
        mutatedContent: String
    ) async throws -> Sandbox {
        let mutatedCanonical = URL(fileURLWithPath: mutatedFilePath).resolvingSymlinksInPath().path

        return try await Self.offCooperativePool {
            try populate(projectPath: projectPath, replacing: [mutatedCanonical: mutatedContent])
        }
    }

    static func offCooperativePool<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func populate(projectPath: String, replacing replacements: [String: String]) throws -> Sandbox {
        let sandboxURL = SandboxName.directory.appendingPathComponent(SandboxName.make())
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        let projectURL = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath()

        try populateDirectory(
            source: projectURL,
            destination: sandboxURL,
            replacements: Replacements(replacements, under: projectURL.path),
            relativePath: "",
            copiesFiles: false
        )

        return Sandbox(rootURL: sandboxURL)
    }

    private struct Replacements {
        let byCanonicalPath: [String: String]
        let byRelativePath: [String: String]

        init(_ byCanonicalPath: [String: String], under root: String) {
            self.byCanonicalPath = byCanonicalPath
            let prefix = root.hasSuffix("/") ? root : root + "/"
            byRelativePath = Dictionary(
                byCanonicalPath.compactMap { path, content in
                    path.hasPrefix(prefix) ? (String(path.dropFirst(prefix.count)), content) : nil
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        var isEmpty: Bool { byCanonicalPath.isEmpty }

        func content(for source: URL, relativePath: String, isSymlink: Bool) -> String? {
            if let content = byRelativePath[relativePath] { return content }
            guard isSymlink else { return nil }
            return byCanonicalPath[source.resolvingSymlinksInPath().path]
        }
    }

    private func populateDirectory(
        source: URL,
        destination: URL,
        replacements: Replacements,
        relativePath: String,
        copiesFiles: Bool
    ) throws {
        let items = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )

        for item in items {
            let name = item.lastPathComponent
            let dest = destination.appendingPathComponent(name)
            let itemRelativePath = relativePath.isEmpty ? name : relativePath + "/" + name
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values.isDirectory == true
            let isSymlink = values.isSymbolicLink == true

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
                    replacements: replacements,
                    relativePath: itemRelativePath,
                    copiesFiles: copiesFiles || (name == "xcshareddata" && source.pathExtension == "xcworkspace")
                )
            } else if !replacements.isEmpty,
                let content = replacements.content(for: item, relativePath: itemRelativePath, isSymlink: isSymlink)
            {
                try content.write(to: dest, atomically: true, encoding: .utf8)
            } else {
                try writeFile(source: item, destination: dest, copiesFiles: copiesFiles)
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
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true

            if isDir && name == "xcuserdata" {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if isDir && name == "xcshareddata" {
                try FileManager.default.copyItem(at: item, to: dest)
            } else {
                try FileManager.default.createSymbolicLink(at: dest, withDestinationURL: item)
            }
        }
    }

    private func writeFile(source: URL, destination: URL, copiesFiles: Bool) throws {
        if copiesFiles {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }

        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func disableSwiftLintBuildPhases(in sandboxURL: URL) throws {
        for xcodeprojURL in Self.xcodeprojs(in: sandboxURL) {
            try disableSwiftLintBuildPhases(inProject: xcodeprojURL)
        }
    }

    private func disableSwiftLintBuildPhases(inProject xcodeprojURL: URL) throws {
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

    static func xcodeprojs(in directory: URL) -> [URL] {
        let skipped: Set<String> = [".build", "DerivedData", "Pods", ".xmr-derived-data", ".derived-data"]
        var found: [URL] = []
        var pending = [directory]
        while let current = pending.popLast() {
            let items =
                (try? FileManager.default.contentsOfDirectory(
                    at: current, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )) ?? []
            for item in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if item.pathExtension == "xcodeproj" {
                    found.append(item)
                } else if !skipped.contains(item.lastPathComponent), item.pathExtension != "xcworkspace" {
                    pending.append(item)
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }
}
