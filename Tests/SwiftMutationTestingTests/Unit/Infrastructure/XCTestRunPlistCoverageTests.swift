import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("XCTestRunPlist — coverage")
struct XCTestRunPlistCoverageTests {
    private func plist(_ dictionary: [String: Any]) throws -> XCTestRunPlist {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        return try #require(XCTestRunPlist(data))
    }

    private func environment(of data: Data) throws -> [String: String] {
        let dict = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let configurations = try #require(dict["TestConfigurations"] as? [[String: Any]])
        let targets = try #require(configurations[0]["TestTargets"] as? [[String: Any]])
        return try #require(targets[0]["EnvironmentVariables"] as? [String: String])
    }

    private let newFormat: [String: Any] = [
        "TestConfigurations": [
            [
                "TestTargets": [
                    [
                        "BlueprintName": "AppTests", "ProductModuleName": "App_Tests",
                        "TestBundlePath": "__TESTROOT__/Debug/App Tests.xctest",
                        "EnvironmentVariables": ["HOME": "/x"],
                    ],
                    ["BlueprintName": "UITests", "TestBundlePath": "__TESTROOT__/Debug/UITests.xctest"],
                ]
            ]
        ]
    ]

    @Test("Given a coverage file, when the baseline plist is made, then the file and the redirect reach the host")
    func aCoverageFileIsPassedWithTheRedirect() throws {
        let data = try plist(newFormat).activating("", coverageFile: "/tmp/coverage.log")

        let env = try environment(of: data)
        #expect(env[SupportDeclarations.coverageEnvironmentVariable] == "/tmp/coverage.log")
        #expect(env[SupportDeclarations.coverageRedirectVariable] == "1")
        #expect(env["HOME"] == "/x")
    }

    @Test("Given no coverage file, when a mutant plist is made, then neither variable is set")
    func noCoverageFileSetsNothing() throws {
        let env = try environment(of: try plist(newFormat).activating("m1", activationFile: "/tmp/m1"))

        #expect(env[SupportDeclarations.coverageEnvironmentVariable] == nil)
        #expect(env[SupportDeclarations.coverageRedirectVariable] == nil)
        #expect(env["__SWIFT_MUTATION_TESTING_ACTIVE"] == "m1")
    }

    @Test("Given the new format, when the target names are read, then modules and bundles map to blueprints")
    func targetNamesFromTheNewFormat() throws {
        let names = try plist(newFormat).targetNames()

        #expect(names == ["App_Tests": "AppTests", "App Tests": "AppTests", "UITests": "UITests"])
    }

    @Test("Given the legacy format, when the target names are read, then each target dictionary is read")
    func targetNamesFromTheLegacyFormat() throws {
        let legacy: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": [
                "BlueprintName": "AppTests", "ProductModuleName": "AppTests",
                "TestBundlePath": "__TESTROOT__/Debug/AppTests.xctest",
            ],
        ]

        #expect(try plist(legacy).targetNames() == ["AppTests": "AppTests"])
    }
}
