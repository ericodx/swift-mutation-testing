import Foundation

@testable import SwiftMutationTesting

func makeSchemaSandbox(
    projectPath: String,
    installed: [SchematizedFile] = []
) async throws -> SchemaSandbox {
    let sandbox = try await SandboxFactory().create(projectPath: projectPath, schematizedFiles: installed)
    return SchemaSandbox(sandbox: sandbox, projectPath: projectPath, installed: installed)
}
