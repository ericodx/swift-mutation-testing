import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProjectDetector")
struct ProjectDetectorTests {
    private let projectJSON = """
        {
          "project": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests"],
            "targets": ["MyApp", "MyAppTests", "MyAppUITests"]
          }
        }
        """

    private let workspaceJSON = """
        {
          "workspace": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests"]
          }
        }
        """

    @Test("Given project JSON with targets, when detect called, then scheme and testTarget are set")
    func detectsSchemeAndTestTargetFromProjectJSON() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == "MyApp")
        #expect(result.allSchemes == ["MyApp", "MyAppTests"])
        #expect(result.testTarget == "MyAppTests")
    }

    @Test("Given project JSON with UITests but no unit tests, when detect called, then UITests target is returned")
    func fallsBackToUITestsWhenNoUnitTests() async throws {
        let json = """
            { "project": { "name": "App", "schemes": ["App"], "targets": ["App", "AppUITests"] } }
            """
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: json))
        let result = await detector.detect(at: dir.path)

        #expect(result.testTarget == "AppUITests")
    }

    @Test("Given workspace JSON without targets, when detect called, then scheme name is used as testTarget hint")
    func detectsTestTargetFromSchemeNamesForWorkspace() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcworkspace"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: workspaceJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == "MyApp")
        #expect(result.testTarget == "MyAppTests")
    }

    @Test("Given xcodeproj with iphoneos SDKROOT, when detect called, then destination is iOS Simulator")
    func detectsiOSDestinationFromPbxproj() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.destination.contains("iOS Simulator"))
    }

    @Test("Given iphoneos SDK and simctl returns iPhone 17 Pro, when detect called, then destination uses it")
    func usesSimctlDeviceForIOSDestination() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
                  { "name": "iPhone 17", "isAvailable": true },
                  { "name": "iPhone 17 Pro", "isAvailable": true }
                ]
              }
            }
            """

        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=iOS Simulator,OS=latest,name=iPhone 17 Pro")
    }

    @Test("Given iphoneos SDK and simctl fails, when detect called, then destination falls back to macOS")
    func fallsBackToMacOSWhenSimctlFails() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 1, output: "")]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=macOS")
    }

    @Test("Given xcodeproj with macosx SDKROOT, when detect called, then destination is macOS")
    func detectsmacOSDestinationFromPbxproj() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = macosx;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.destination == "platform=macOS")
    }

    @Test("Given aggregate and app schemes, when detect called, then app scheme matching project name is selected")
    func selectsSchemeMatchingProjectName() async throws {
        let json = """
            {
              "project": {
                "name": "MyApp",
                "schemes": ["AggregateAll", "MyApp"],
                "targets": ["MyApp", "MyAppTests"]
              }
            }
            """
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: json))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == "MyApp")
        #expect(result.allSchemes == ["AggregateAll", "MyApp"])
    }

    @Test("Given xcodebuild exits with non-zero code, when detect called, then empty project is returned")
    func returnsEmptyWhenXcodebuildFails() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 1, output: ""))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }

    @Test("Given directory with no Xcode container, when detect called, then empty project is returned")
    func returnsEmptyWhenNoContainerFound() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }

    @Test("Given malformed JSON, when detect called, then empty project is returned")
    func returnsEmptyForMalformedJSON() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: "not json"))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }

    @Test("Given detect called with dot path, when resolved, then uses current directory")
    func resolvesDotPathToCurrentDirectory() async {
        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: "{}"))
        let result = await detector.detect(at: ".")
        #expect(result.scheme == nil)
    }

    @Test("Given nonexistent project path, when detect called, then returns empty project")
    func returnsEmptyForNonexistentPath() async {
        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: "{}"))
        let result = await detector.detect(at: "/nonexistent/path/that/does/not/exist")
        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }

    @Test("Given detect called with empty path, when resolved, then uses current directory")
    func resolvesEmptyPathToCurrentDirectory() async {
        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: "{}"))
        let result = await detector.detect(at: "")
        #expect(result.scheme == nil)
    }

    @Test("Given xcodeproj with appletvos SDKROOT, when detect called, then destination is tvOS Simulator")
    func detectstvOSDestinationFromPbxproj() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = appletvos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.tvOS-17-0": [
                  { "name": "Apple TV 4K (3rd generation)", "isAvailable": true }
                ]
              }
            }
            """
        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination.contains("tvOS Simulator"))
        #expect(result.destination.contains("Apple TV 4K"))
    }

    @Test("Given xcodeproj with watchos SDKROOT, when detect called, then destination is watchOS Simulator")
    func detectswatchOSDestinationFromPbxproj() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = watchos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.watchOS-10-0": [
                  { "name": "Apple Watch Series 10 (46mm)", "isAvailable": true }
                ]
              }
            }
            """
        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination.contains("watchOS Simulator"))
        #expect(result.destination.contains("Apple Watch"))
    }

    @Test("Given appletvos SDK and simctl fails, when detect called, then destination falls back to macOS")
    func fallsBackToMacOSWhenNotvOSSimulatorFound() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = appletvos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 1, output: "")]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=macOS")
    }

    @Test("Given watchos SDK and simctl fails, when detect called, then destination falls back to macOS")
    func fallsBackToMacOSWhenNowatchOSSimulatorFound() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = watchos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 1, output: "")]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=macOS")
    }

    @Test("Given project JSON with no schemes at all, when detect called, then scheme is nil")
    func returnsNilSchemeWhenNoSchemes() async throws {
        let json = #"{"project":{"name":"App","schemes":[],"targets":[]}}"#
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )

        let result = await ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: json))
            .detect(at: dir.path)

        #expect(result.scheme == nil)
    }

    @Test("Given iphoneos SDK and multiple iOS runtimes, when detect called, then picks device from latest runtime")
    func picksDeviceFromLatestRuntimeWhenMultipleIOSRuntimesAvailable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
                  { "name": "iPhone 15 Pro", "isAvailable": true }
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                  { "name": "iPhone 16 Pro", "isAvailable": true }
                ]
              }
            }
            """

        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=iOS Simulator,OS=latest,name=iPhone 16 Pro")
    }

    @Test("Given iphoneos SDK and runtime with no iPhone devices, when detect called, then falls back to macOS")
    func fallsBackToMacOSWhenRuntimeHasNoIPhoneDevices() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                  { "name": "iPad Air", "isAvailable": true }
                ]
              }
            }
            """

        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=macOS")
    }

    @Test("Given iphoneos SDK and simctl returns iPhone without Pro, when detect called, then uses iPhone")
    func usesIPhoneWithoutProWhenNoProAvailable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                  { "name": "iPhone 16", "isAvailable": true }
                ]
              }
            }
            """
        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination == "platform=iOS Simulator,OS=latest,name=iPhone 16")
    }
}
