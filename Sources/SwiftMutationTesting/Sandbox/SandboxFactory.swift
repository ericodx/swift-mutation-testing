import Foundation

struct SandboxFactory: Sendable {
    var warm: WarmSandboxes?

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
        let projectURL = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath()
        var replacements = Replacements(replacements, under: projectURL.path)
        let sandbox: Sandbox

        if let warm {
            let (sandboxURL, slot) = try warm.claim(projectPath: projectPath)
            sandbox = Sandbox(rootURL: sandboxURL, slot: slot)
            do {
                replacements.kept = replacements.unchanged(in: sandboxURL)
                try warm.prune(sandboxURL, keeping: replacements.kept)
            } catch {
                slot.unlock()
                throw error
            }
        } else {
            let sandboxURL = SandboxName.directory.appendingPathComponent(SandboxName.make())
            try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
            sandbox = Sandbox(rootURL: sandboxURL)
        }

        do {
            try populateDirectory(
                source: projectURL,
                destination: sandbox.rootURL,
                replacements: replacements,
                relativePath: ""
            )
        } catch {
            sandbox.slot?.unlock()
            throw error
        }

        return sandbox
    }

    struct Replacements {
        let byCanonicalPath: [String: String]
        let byRelativePath: [String: String]
        var kept: Set<String> = []

        init(_ byCanonicalPath: [String: String], under root: String) {
            self.byCanonicalPath = byCanonicalPath
            let prefix = root.hasSuffix("/") ? root : root + "/"
            byRelativePath = Uniquing.keepingFirst(
                byCanonicalPath.compactMap { path, content in
                    path.hasPrefix(prefix) ? (String(path.dropFirst(prefix.count)), content) : nil
                }
            )
        }

        var isEmpty: Bool { byCanonicalPath.isEmpty }

        func content(for source: URL, relativePath: String, isSymlink: Bool) -> String? {
            if let content = byRelativePath[relativePath] { return content }
            guard isSymlink else { return nil }
            return byCanonicalPath[source.resolvingSymlinksInPath().path]
        }

        func unchanged(in sandboxURL: URL) -> Set<String> {
            Set(
                byRelativePath.compactMap { relativePath, content in
                    let url = sandboxURL.appendingPathComponent(relativePath)
                    guard
                        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false,
                        let existing = try? String(contentsOf: url, encoding: .utf8),
                        existing == LintSuppression.wrapping(content)
                    else { return nil }
                    return relativePath
                }
            )
        }
    }

    private func populateDirectory(
        source: URL,
        destination: URL,
        replacements: Replacements,
        relativePath: String
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
                    relativePath: itemRelativePath
                )
            } else if !replacements.isEmpty,
                let content = replacements.content(for: item, relativePath: itemRelativePath, isSymlink: isSymlink)
            {
                guard !replacements.kept.contains(itemRelativePath) else { continue }
                try LintSuppression.wrapping(content).write(to: dest, atomically: true, encoding: .utf8)
            } else {
                try writeFile(source: item, destination: dest, isSymlink: isSymlink)
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

    private func writeFile(source: URL, destination: URL, isSymlink: Bool) throws {
        if isSymlink || source.pathExtension == "swift" {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
            return
        }

        try FileManager.default.copyItem(at: source, to: destination)
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
