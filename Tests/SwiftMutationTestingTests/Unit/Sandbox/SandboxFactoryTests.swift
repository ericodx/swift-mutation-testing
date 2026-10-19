import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxFactory")
struct SandboxFactoryTests {
    private let factory = SandboxFactory()

    @Test("Given schematized files, when sandbox created, then schematized content is written to sandbox")
    func writesSchematizedContent() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("original content", named: "File.swift", in: projectDir)
        let filePath = projectDir.appendingPathComponent("File.swift").path

        let schematized = SchematizedFile(originalPath: filePath, schematizedContent: "schematized content")
        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [schematized]
        )
        defer { try? sandbox.cleanup() }

        let content = try String(
            contentsOf: sandbox.rootURL.appendingPathComponent("File.swift"),
            encoding: .utf8
        )

        #expect(content == LintSuppression.wrapping("schematized content"))
    }

    @Test("Given a project, when sandbox created, then it lives in the sandbox directory, not loose in temp")
    func createsSandboxInsideSandboxDirectory() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }
        try FileHelpers.write("let x = 1", named: "Main.swift", in: projectDir)

        let sandbox = try await factory.createClean(projectPath: projectDir.path)
        defer { try? sandbox.cleanup() }

        #expect(
            sandbox.rootURL.deletingLastPathComponent().standardizedFileURL
                == SandboxName.directory.standardizedFileURL
        )
    }

    @Test("Given xcodeproj directory, when sandbox created, then xcuserdata is empty directory not a symlink")
    func xcodeprojXcuserdataIsEmptyDirectory() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcuserdataDir =
            projectDir
            .appendingPathComponent("App.xcodeproj/xcuserdata")
        try FileManager.default.createDirectory(at: xcuserdataDir, withIntermediateDirectories: true)
        try FileHelpers.write("user data", named: "user.xcuserdatad", in: xcuserdataDir)

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        let sandboxXcuserdata = sandbox.rootURL.appendingPathComponent("App.xcodeproj/xcuserdata")
        let isSymlink = (try? sandboxXcuserdata.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        let userDataFile = sandboxXcuserdata.appendingPathComponent("user.xcuserdatad")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sandboxXcuserdata.path, isDirectory: &isDir)

        #expect(exists)
        #expect(isDir.boolValue)
        #expect(!isSymlink)
        #expect(!FileManager.default.fileExists(atPath: userDataFile.path))
    }

    @Test("Given xcodeproj with shared data and a workspace, when sandbox created, then only shared data is copied")
    func xcodeprojCopiesSharedDataAndLinksTheRest() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcodeproj = projectDir.appendingPathComponent("App.xcodeproj")
        let schemesDir = xcodeproj.appendingPathComponent("xcshareddata/xcschemes")
        let workspaceDir = xcodeproj.appendingPathComponent("project.xcworkspace")
        try FileManager.default.createDirectory(at: schemesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        try FileHelpers.write("<Scheme/>", named: "App.xcscheme", in: schemesDir)
        try FileHelpers.write("<Workspace/>", named: "contents.xcworkspacedata", in: workspaceDir)

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        func isSymlink(_ relative: String) -> Bool {
            let url = sandbox.rootURL.appendingPathComponent(relative)
            return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        }
        let scheme = sandbox.rootURL.appendingPathComponent("App.xcodeproj/xcshareddata/xcschemes/App.xcscheme")

        #expect(try String(contentsOf: scheme, encoding: .utf8) == "<Scheme/>")
        #expect(!isSymlink("App.xcodeproj/xcshareddata"))
        #expect(isSymlink("App.xcodeproj/project.xcworkspace"))
    }

    @Test("Given file not in schematized list, when sandbox created, then file is a symlink to the original")
    func nonSchematizedFileIsSymlink() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("original content", named: "Unchanged.swift", in: projectDir)

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        let sandboxFile = sandbox.rootURL.appendingPathComponent("Unchanged.swift")
        let isSymlink = (try? sandboxFile.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        let content = try String(contentsOf: sandboxFile, encoding: .utf8)

        #expect(isSymlink)
        #expect(content == "original content")
    }

    @Test("Given an Icon Composer bundle, when sandbox created, then its manifest and nested assets are copied")
    func iconComposerBundleCopiesFiles() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let iconDir = projectDir.appendingPathComponent("AppIcon.icon")
        let assetsDir = iconDir.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try FileHelpers.write("{}", named: "icon.json", in: iconDir)
        try FileHelpers.write("<svg/>", named: "dot.svg", in: assetsDir)
        try FileHelpers.write("let x = 1", named: "Main.swift", in: projectDir)

        let sandbox = try await factory.createClean(projectPath: projectDir.path)
        defer { try? sandbox.cleanup() }

        func isSymlink(_ relative: String) -> Bool {
            let url = sandbox.rootURL.appendingPathComponent(relative)
            return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        }
        func content(_ relative: String) throws -> String {
            try String(contentsOf: sandbox.rootURL.appendingPathComponent(relative), encoding: .utf8)
        }

        #expect(!isSymlink("AppIcon.icon/icon.json"))
        #expect(!isSymlink("AppIcon.icon/Assets/dot.svg"))
        #expect(try content("AppIcon.icon/icon.json") == "{}")
        #expect(try content("AppIcon.icon/Assets/dot.svg") == "<svg/>")
        #expect(isSymlink("Main.swift"))
    }

    @Test("Given mutated file path and content, when single-file sandbox created, then mutated content is written")
    func writesMutatedContentInSingleFileSandbox() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("original content", named: "File.swift", in: projectDir)
        let filePath = projectDir.appendingPathComponent("File.swift").path

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            mutatedFilePath: filePath,
            mutatedContent: "mutated content"
        )
        defer { try? sandbox.cleanup() }

        let content = try String(
            contentsOf: sandbox.rootURL.appendingPathComponent("File.swift"),
            encoding: .utf8
        )

        #expect(content == LintSuppression.wrapping("mutated content"))
    }

    @Test("Given xcodeproj with swiftlint build phase, when sandbox created, then shellScript is replaced with exit 0")
    func disablesSwiftLintBuildPhase() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcodeprojDir = projectDir.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojDir, withIntermediateDirectories: true)
        try swiftLintPbxprojContent().write(
            to: xcodeprojDir.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        let sandboxPbxproj = sandbox.rootURL
            .appendingPathComponent("App.xcodeproj/project.pbxproj")
        let data = try Data(contentsOf: sandboxPbxproj)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist =
            try PropertyListSerialization.propertyList(
                from: data, options: [], format: &format
            ) as? [String: Any]
        let objects = plist?["objects"] as? [String: Any]
        let lintPhase = objects?["AABBCC"] as? [String: Any]
        let otherPhase = objects?["DDEEFF"] as? [String: Any]

        #expect(lintPhase?["shellScript"] as? String == "exit 0\n")
        #expect(otherPhase?["shellScript"] as? String == "echo hello")
    }

    @Test("Given xcworkspace with xcshareddata file, when sandbox created, then xcshareddata file is copied")
    func xcworkspaceXcsharedDataFileIsCopied() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcshareddataDir =
            projectDir
            .appendingPathComponent("App.xcworkspace/xcshareddata")
        try FileManager.default.createDirectory(at: xcshareddataDir, withIntermediateDirectories: true)
        try "shared content".write(
            to: xcshareddataDir.appendingPathComponent("scheme.xcscheme"),
            atomically: true, encoding: .utf8
        )

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        let sandboxFile = sandbox.rootURL
            .appendingPathComponent("App.xcworkspace/xcshareddata/scheme.xcscheme")
        let isSymlink = (try? sandboxFile.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        #expect(!isSymlink)
        let content = try String(contentsOf: sandboxFile, encoding: .utf8)
        #expect(content == "shared content")
    }

    @Test("Given build output directories, when sandbox created, then they are not replicated")
    func skipsBuildOutputDirectories() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("let kept = true", named: "File.swift", in: projectDir)

        for skipped in [".build", "DerivedData", ".xmr-cache"] {
            let directory = projectDir.appendingPathComponent(skipped)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileHelpers.write("stale", named: "artifact.o", in: directory)
        }

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        for skipped in [".build", "DerivedData", ".xmr-cache"] {
            #expect(
                !FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent(skipped).path),
                "\(skipped) should not be replicated into the sandbox"
            )
        }
        #expect(FileManager.default.fileExists(atPath: sandbox.rootURL.appendingPathComponent("File.swift").path))
    }

    @Test("Given created sandbox, when cleanup called, then sandbox directory no longer exists")
    func cleanupRemovesSandboxDirectory() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: []
        )

        try sandbox.cleanup()

        #expect(!FileManager.default.fileExists(atPath: sandbox.rootURL.path))
    }

    @Test("Given a pbxproj that is not a property list, when the sandbox is created, then it is left as it is")
    func aPbxprojThatIsNotAPropertyListIsLeftAlone() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcodeproj = projectDir.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try "this is not a plist".write(
            to: xcodeproj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8
        )

        let sandbox = try await factory.create(
            projectPath: projectDir.path, schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        let copied = try String(
            contentsOf: sandbox.rootURL.appendingPathComponent("App.xcodeproj/project.pbxproj"), encoding: .utf8
        )

        #expect(copied == "this is not a plist")
    }

    @Test("Given a pbxproj with no objects, when the sandbox is created, then it is left as it is")
    func aPbxprojWithoutObjectsIsLeftAlone() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcodeproj = projectDir.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>archiveVersion</key>
                <string>1</string>
            </dict>
            </plist>
            """
        try plist.write(
            to: xcodeproj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8
        )

        let sandbox = try await factory.create(
            projectPath: projectDir.path, schematizedFiles: []
        )
        defer { try? sandbox.cleanup() }

        let copied = try String(
            contentsOf: sandbox.rootURL.appendingPathComponent("App.xcodeproj/project.pbxproj"), encoding: .utf8
        )

        #expect(copied.contains("archiveVersion"))
        #expect(!copied.contains("exit 0"))
    }

    @Test("Given the first schematized file lies outside the project, when created, then it is not written")
    func aSchematizedFileOutsideTheProjectIsNotWritten() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        let elsewhere = try FileHelpers.makeTemporaryDirectory()
        defer {
            FileHelpers.cleanup(projectDir)
            FileHelpers.cleanup(elsewhere)
        }

        try FileHelpers.write("original", named: "File.swift", in: projectDir)
        let outside = elsewhere.appendingPathComponent("Outside.swift")
        try "let x = 1".write(to: outside, atomically: true, encoding: .utf8)

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [SchematizedFile(originalPath: outside.path, schematizedContent: "let x = 2")]
        )
        defer { try? sandbox.cleanup() }

        let entries = try FileManager.default.contentsOfDirectory(atPath: sandbox.rootURL.path)

        #expect(entries == ["File.swift"])
    }

    @Test(
        "Given a workspace whose projects sit in subdirectories, when sandboxed, then every project's SwiftLint phase is off"
    )
    func disablesSwiftLintInEveryProject() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }
        let projects = ["App.xcodeproj", "Core/Core.xcodeproj", "Libs/Net/Net.xcodeproj", "Pods/Pods.xcodeproj"]
        for project in projects {
            let dir = projectDir.appendingPathComponent(project)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try swiftLintPbxprojContent().write(
                to: dir.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8
            )
        }

        let sandbox = try await factory.create(projectPath: projectDir.path, schematizedFiles: [])
        defer { try? sandbox.cleanup() }

        for project in projects {
            let data = try Data(contentsOf: sandbox.rootURL.appendingPathComponent("\(project)/project.pbxproj"))
            var format = PropertyListSerialization.PropertyListFormat.xml
            let plist =
                try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any]
            let lintPhase = (plist?["objects"] as? [String: Any])?["AABBCC"] as? [String: Any]
            let script = lintPhase?["shellScript"] as? String
            if project.hasPrefix("Pods/") {
                #expect(script != "exit 0\n", "Pods/ is not looked into")
            } else {
                #expect(script == "exit 0\n", "\(project)")
            }
        }
        let root = CanonicalPath.make(for: sandbox.rootURL.path)
        #expect(
            SandboxFactory.xcodeprojs(in: sandbox.rootURL).map {
                String(CanonicalPath.make(for: $0.path).dropFirst(root.count + 1))
            } == ["App.xcodeproj", "Core/Core.xcodeproj", "Libs/Net/Net.xcodeproj"]
        )
    }
}
