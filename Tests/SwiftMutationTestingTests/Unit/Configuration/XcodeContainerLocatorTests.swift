import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("XcodeContainerLocator")
struct XcodeContainerLocatorTests {
    @Test("Given one workspace and its projects at the root, when located, then the workspace is the container")
    func aSingleWorkspaceWins() throws {
        let root = try Self.root(["App.xcworkspace", "App.xcodeproj", "Core.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        #expect(
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil) == .workspace("App.xcworkspace"))
    }

    @Test("Given no workspace and one project, when located, then the project is the container")
    func aSingleProjectWins() throws {
        let root = try Self.root(["App.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        #expect(try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil) == .project("App.xcodeproj"))
    }

    @Test("Given nothing Xcode at the root, when located, then there is no container")
    func nothingAtTheRoot() throws {
        let root = try Self.root([])
        defer { FileHelpers.cleanup(root) }

        #expect(try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil) == nil)
    }

    @Test("Given two workspaces, or two projects and no workspace, when located, then the error names them all")
    func ambiguityIsAnError() throws {
        let workspaces = try Self.root(["Tools.xcworkspace", "App.xcworkspace", "App.xcodeproj"])
        defer { FileHelpers.cleanup(workspaces) }
        let projects = try Self.root(["B.xcodeproj", "A.xcodeproj"])
        defer { FileHelpers.cleanup(projects) }

        #expect(
            throws: UsageError(
                message:
                    "found App.xcworkspace and Tools.xcworkspace at the project root; pass --workspace (or the `workspace` key) to choose one"
            )
        ) {
            try XcodeContainerLocator.locate(in: workspaces, workspace: nil, project: nil)
        }
        #expect(
            throws: UsageError(
                message:
                    "found A.xcodeproj and B.xcodeproj at the project root; pass --project (or the `project` key) to choose one"
            )
        ) {
            try XcodeContainerLocator.locate(in: projects, workspace: nil, project: nil)
        }
    }

    @Test("Given an explicit workspace in a subdirectory, when located, then it is taken, even beside others")
    func anExplicitWorkspaceInASubdirectory() throws {
        let root = try Self.root(["Tools.xcworkspace", "App.xcworkspace", "Apps/Main.xcworkspace"])
        defer { FileHelpers.cleanup(root) }

        #expect(
            try XcodeContainerLocator.locate(in: root, workspace: "Apps/Main.xcworkspace", project: nil)
                == .workspace("Apps/Main.xcworkspace")
        )
        #expect(
            try XcodeContainerLocator.locate(in: root, workspace: root.path + "/App.xcworkspace", project: nil)
                == .workspace("App.xcworkspace")
        )
    }

    @Test("Given an explicit project, when located, then it is taken")
    func anExplicitProject() throws {
        let root = try Self.root(["A.xcodeproj", "B.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        #expect(
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: "B.xcodeproj")
                == .project("B.xcodeproj"))
    }

    @Test(
        "Given a container that is missing, of the wrong kind, outside the root, or both kinds, when located, then each is refused"
    )
    func badExplicitContainers() throws {
        let root = try Self.root(["A.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        #expect(throws: UsageError.self) {
            try XcodeContainerLocator.locate(in: root, workspace: "Missing.xcworkspace", project: nil)
        }
        #expect(throws: UsageError.self) {
            try XcodeContainerLocator.locate(in: root, workspace: "A.xcodeproj", project: nil)
        }
        #expect(throws: UsageError.self) {
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: "../A.xcodeproj")
        }
        #expect(throws: UsageError(message: "--workspace and --project cannot be used together; give one container")) {
            try XcodeContainerLocator.locate(in: root, workspace: "W.xcworkspace", project: "A.xcodeproj")
        }
    }

    @Test("Given a workspace whose groups reach projects inside the root, when located, then they are its projects")
    func workspaceReferencesInsideTheRoot() throws {
        let root = try Self.root(["App.xcworkspace", "App/App.xcodeproj", "Libs/Core/Core.xcodeproj"])
        defer { FileHelpers.cleanup(root) }
        try Self.contents(
            """
            <Workspace version = "1.0">
               <FileRef location = "group:App/App.xcodeproj"></FileRef>
               <Group location = "group:Libs" name = "Libs">
                  <FileRef location = "group:Core/Core.xcodeproj"></FileRef>
               </Group>
               <FileRef location = "self:"></FileRef>
            </Workspace>
            """, of: "App.xcworkspace", in: root
        )

        #expect(
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil) == .workspace("App.xcworkspace"))
        #expect(
            XcodeContainerLocator.projects(referencedBy: "App.xcworkspace", in: root)
                == ["App/App.xcodeproj", "Libs/Core/Core.xcodeproj"]
        )
    }

    @Test("Given a workspace that references a project outside the root, when located, then it is refused by name")
    func workspaceReferencesOutsideTheRoot() throws {
        let root = try Self.root(["App.xcworkspace"])
        defer { FileHelpers.cleanup(root) }
        try Self.contents(
            """
            <Workspace version = "1.0">
               <FileRef location = "group:../Shared/Shared.xcodeproj"></FileRef>
            </Workspace>
            """, of: "App.xcworkspace", in: root
        )

        #expect {
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil)
        } throws: { error in
            (error as? UsageError)?.message.contains("references") == true
                && (error as? UsageError)?.message.contains("Shared/Shared.xcodeproj") == true
                && (error as? UsageError)?.message.contains("outside the project root") == true
        }
    }

    @Test("Given containers only below the root, when located, then the run is refused with them as suggestions")
    func containersBelowTheRootAreSuggested() throws {
        let root = try Self.root([
            "Apps/App.xcworkspace", "Apps/App.xcodeproj", "Apps/App.xcodeproj/project.xcworkspace",
            "Pods/Pods.xcodeproj", ".build/Hidden.xcodeproj", "a/b/c/d/Deep.xcodeproj",
        ])
        defer { FileHelpers.cleanup(root) }

        #expect(
            XcodeContainerLocator.nestedCandidates(in: root)
                == .init(workspaces: ["Apps/App.xcworkspace"], projects: ["Apps/App.xcodeproj"])
        )
        #expect(
            throws: UsageError(
                message: "no .xcworkspace or .xcodeproj at the project root, but found Apps/App.xcworkspace and "
                    + "Apps/App.xcodeproj below it; pass --workspace or --project (or the `workspace` / `project` key) "
                    + "with the one to build"
            )
        ) {
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil)
        }
        #expect(
            try XcodeContainerLocator.locate(in: root, workspace: "Apps/App.xcworkspace", project: nil)
                == .workspace("Apps/App.xcworkspace")
        )
    }

    @Test("Given every kind of workspace location, when its projects are read, then each resolves against its base")
    func everyLocationKindResolves() throws {
        let root = try Self.root(["App.xcworkspace"])
        defer { FileHelpers.cleanup(root) }
        try Self.contents(
            """
            <Workspace version = "1.0">
               <Group name = "Unnamed">
                  <FileRef location = "group:App/App.xcodeproj"></FileRef>
               </Group>
               <Group location = "group:">
                  <FileRef location = "group:Same/Same.xcodeproj"></FileRef>
               </Group>
               <Group location = "container:">
                  <FileRef location = "group:Root/Root.xcodeproj"></FileRef>
               </Group>
               <FileRef location = "container:Libs/Core/Core.xcodeproj"></FileRef>
               <FileRef location = "absolute:/elsewhere/Out.xcodeproj"></FileRef>
               <FileRef location = "nocolon.xcodeproj"></FileRef>
            </Workspace>
            """, of: "App.xcworkspace", in: root
        )

        #expect(
            XcodeContainerLocator.projects(referencedBy: "App.xcworkspace", in: root) == [
                "App/App.xcodeproj", "Same/Same.xcodeproj", "Root/Root.xcodeproj", "Libs/Core/Core.xcodeproj",
                "/elsewhere/Out.xcodeproj",
            ]
        )
    }

    @Test("Given a workspace with no contents file, when its projects are read, then there are none")
    func aWorkspaceWithoutContentsHasNoProjects() throws {
        let root = try Self.root(["App.xcworkspace"])
        defer { FileHelpers.cleanup(root) }

        #expect(XcodeContainerLocator.projects(referencedBy: "App.xcworkspace", in: root).isEmpty)
    }

    @Test("Given workspaces referencing three projects outside the root, when located, then all three are named")
    func severalOutsideReferencesAreListed() throws {
        let root = try Self.root(["App.xcworkspace"])
        defer { FileHelpers.cleanup(root) }
        try Self.contents(
            """
            <Workspace version = "1.0">
               <FileRef location = "absolute:/a/A.xcodeproj"></FileRef>
               <FileRef location = "absolute:/b/B.xcodeproj"></FileRef>
               <FileRef location = "absolute:/c/C.xcodeproj"></FileRef>
            </Workspace>
            """, of: "App.xcworkspace", in: root
        )

        #expect {
            try XcodeContainerLocator.locate(in: root, workspace: nil, project: nil)
        } throws: { error in
            (error as? UsageError)?.message.contains("/a/A.xcodeproj, /b/B.xcodeproj and /c/C.xcodeproj") == true
        }
    }

    // MARK: - Fixture

    static func root(_ directories: [String]) throws -> URL {
        let root = try FileHelpers.makeTemporaryDirectory()
        for directory in directories {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory), withIntermediateDirectories: true
            )
        }
        return root
    }

    static func contents(_ xml: String, of workspace: String, in root: URL) throws {
        try xml.write(
            to: root.appendingPathComponent(workspace).appendingPathComponent("contents.xcworkspacedata"),
            atomically: true, encoding: .utf8
        )
    }

    @Test("Given a file system of its own, when candidates are listed, then they come from it and not from disk")
    func candidatesComeFromTheFileSystemGiven() {
        var fileSystem = FileSystem()
        fileSystem.contentsOfDirectory = { _ in ["B.xcodeproj", "A.xcworkspace", "README.md", "A.xcodeproj"] }

        let found = XcodeContainerLocator.candidates(in: URL(fileURLWithPath: "/nowhere"), fileSystem: fileSystem)

        #expect(found.workspaces == ["A.xcworkspace"])
        #expect(found.projects == ["A.xcodeproj", "B.xcodeproj"])
    }
}
