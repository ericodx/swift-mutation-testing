import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("XCTestRunPlist")
struct XCTestRunPlistTests {
    @Test("Given invalid data, when initialized, then returns nil")
    func initReturnsNilForInvalidPlist() {
        let plist = XCTestRunPlist(Data("not a plist".utf8))

        #expect(plist == nil)
    }

    @Test("Given valid plist data, when initialized, then returns non-nil instance")
    func initSucceedsForValidPlist() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["__xctestrun_metadata__": ["FormatVersion": 1]],
            format: .xml,
            options: 0
        )

        let plist = XCTestRunPlist(data)

        #expect(plist != nil)
    }

    @Test("Given new-format plist, when activating mutant, then env var is injected into TestTargets")
    func activatingInjectsEnvVarInNewFormat() throws {
        let plistDict: [String: Any] = [
            "TestConfigurations": [
                [
                    "Name": "Config",
                    "TestTargets": [
                        ["BlueprintName": "AppTests", "EnvironmentVariables": [:] as [String: String]]
                    ],
                ] as [String: Any]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))

        let result = plist.activating("id_0")
        let resultDict = try #require(
            PropertyListSerialization.propertyList(from: result, options: [], format: nil) as? [String: Any]
        )
        let configs = try #require(resultDict["TestConfigurations"] as? [[String: Any]])
        let targets = try #require(configs[0]["TestTargets"] as? [[String: Any]])
        let envVars = try #require(targets[0]["EnvironmentVariables"] as? [String: String])

        #expect(envVars["__SWIFT_MUTATION_TESTING_ACTIVE"] == "id_0")
    }

    @Test("Given legacy-format plist, when activating mutant, then env var is injected into target dict")
    func activatingInjectsEnvVarInLegacyFormat() throws {
        let plistDict: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["EnvironmentVariables": [:] as [String: String]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))

        let result = plist.activating("id_1")
        let resultDict = try #require(
            PropertyListSerialization.propertyList(from: result, options: [], format: nil) as? [String: Any]
        )
        let targetDict = try #require(resultDict["AppTests"] as? [String: Any])
        let envVars = try #require(targetDict["EnvironmentVariables"] as? [String: String])

        #expect(envVars["__SWIFT_MUTATION_TESTING_ACTIVE"] == "id_1")
    }

    @Test("Given legacy-format plist with non-dict value key, when activating mutant, then non-dict key is skipped")
    func activatingSkipsNonDictValueKeyInLegacyFormat() throws {
        let plistDict: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["EnvironmentVariables": [:] as [String: String]],
            "versionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))

        let result = plist.activating("id_x")
        let resultDict = try #require(
            PropertyListSerialization.propertyList(from: result, options: [], format: nil) as? [String: Any]
        )

        #expect(resultDict["versionString"] as? String == "1.0")
        let appTests = try #require(resultDict["AppTests"] as? [String: Any])
        let envVars = try #require(appTests["EnvironmentVariables"] as? [String: String])
        #expect(envVars["__SWIFT_MUTATION_TESTING_ACTIVE"] == "id_x")
    }

    @Test("Given legacy-format plist, when activating mutant, then metadata key is not modified")
    func activatingDoesNotModifyMetadataKey() throws {
        let plistDict: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["EnvironmentVariables": [:] as [String: String]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plist = try #require(XCTestRunPlist(data))

        let result = plist.activating("id_2")
        let resultDict = try #require(
            PropertyListSerialization.propertyList(from: result, options: [], format: nil) as? [String: Any]
        )
        let metadata = try #require(resultDict["__xctestrun_metadata__"] as? [String: Any])

        #expect(metadata["EnvironmentVariables"] == nil)
    }
}
