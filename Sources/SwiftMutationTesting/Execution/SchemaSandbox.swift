import Foundation

actor SchemaSandbox {
    nonisolated let sandbox: Sandbox
    private let installer: SchemaInstaller
    private(set) var installed: [SchematizedFile]

    init(sandbox: Sandbox, projectPath: String, installed: [SchematizedFile]) {
        self.sandbox = sandbox
        self.installer = SchemaInstaller(sandbox: sandbox, projectPath: projectPath)
        self.installed = installed
    }

    func install(_ files: [SchematizedFile]) throws {
        try installer.install(files, replacing: installed)
        installed = files
    }

    func restore() throws {
        try install([])
    }
}
