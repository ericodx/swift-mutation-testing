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
            arguments: [],
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
            arguments: XcodeContainer.workspace("App.xcworkspace").arguments,
            timeout: 60
        )

        #expect(request.arguments.suffix(2) == ["-workspace", "App.xcworkspace"])
    }

    @Test("Given arguments, when an Xcode build is requested, then they come after the ones the tool sets")
    func buildForTestingAppendsTheArguments() {
        let request = ToolRequests.buildForTesting(
            in: Sandbox(rootURL: URL(fileURLWithPath: "/tmp/sandbox")),
            scheme: "App",
            destination: "platform=macOS",
            arguments: ["-allowProvisioningUpdates"],
            timeout: 60
        )

        #expect(request.arguments.first == "build-for-testing")
        #expect(request.arguments.last == "-allowProvisioningUpdates")
        #expect(request.arguments.dropLast().suffix(2) == ["-skipMacroValidation", "COMPILER_INDEX_STORE_ENABLE=NO"])
    }

    @Test("Given an SPM build, when requested, then the index store is off")
    func swiftBuildTestsTurnsTheIndexStoreOff() {
        let request = ToolRequests.swiftBuildTests(
            in: Sandbox(rootURL: URL(fileURLWithPath: "/tmp/sandbox")), timeout: 60
        )

        #expect(request.arguments == ["build", "--build-tests", "--disable-index-store"])
    }

    @Test("Given an Xcode build, when requested, then the index store is off, before the given arguments")
    func buildForTestingTurnsTheIndexStoreOffBeforeTheArguments() {
        let request = ToolRequests.buildForTesting(
            in: Sandbox(rootURL: URL(fileURLWithPath: "/tmp/sandbox")),
            scheme: "App",
            destination: "platform=macOS",
            arguments: ["COMPILER_INDEX_STORE_ENABLE=YES"],
            timeout: 60
        )

        #expect(request.arguments.suffix(2) == ["COMPILER_INDEX_STORE_ENABLE=NO", "COMPILER_INDEX_STORE_ENABLE=YES"])
    }
}
