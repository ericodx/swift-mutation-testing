import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ToolRequests")
struct ToolRequestsTests {
    @Test("Given an Xcode build, when requested, then package plugin and macro validation are skipped")
    func buildForTestingSkipsPackageValidation() {
        let request = ToolRequests.buildForTesting(
            in: Sandbox(rootURL: URL(fileURLWithPath: "/tmp/sandbox")),
            scheme: "App",
            destination: "platform=macOS",
            container: nil,
            timeout: 60
        )

        #expect(request.arguments.contains("-skipPackagePluginValidation"))
        #expect(request.arguments.contains("-skipMacroValidation"))
    }

    @Test("Given an Xcode build with a container, when requested, then the container arguments come last")
    func buildForTestingKeepsContainerLast() {
        let request = ToolRequests.buildForTesting(
            in: Sandbox(rootURL: URL(fileURLWithPath: "/tmp/sandbox")),
            scheme: "App",
            destination: "platform=macOS",
            container: .workspace("App.xcworkspace"),
            timeout: 60
        )

        #expect(request.arguments.suffix(2) == ["-workspace", "App.xcworkspace"])
    }
}
