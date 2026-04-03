import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SimulatorManager")
struct SimulatorManagerTests {
    @Test("Given iOS Simulator destination, when requiresSimulatorPool called, then returns true")
    func requiresSimulatorPoolReturnsTrueForIOSSimulator() {
        let result = SimulatorManager.requiresSimulatorPool(for: "platform=iOS Simulator,name=iPhone 15")

        #expect(result)
    }

    @Test("Given macOS destination, when requiresSimulatorPool called, then returns false")
    func requiresSimulatorPoolReturnsFalseForMacOS() {
        let result = SimulatorManager.requiresSimulatorPool(for: "platform=macOS,arch=arm64")

        #expect(!result)
    }

    @Test("Given destination with name, when resolveBaseUDID called, then returns matching UDID")
    func resolveBaseUDIDFindsDeviceByName() async throws {
        let json = SimulatorCommandMock.bootedDevicesJSON(udid: "FOUND-UDID", name: "iPhone 15")
        let manager = SimulatorManager(launcher: SimulatorCommandMock(listOutput: json, cloneUDID: ""))

        let udid = try await manager.resolveBaseUDID(for: "platform=iOS Simulator,name=iPhone 15")

        #expect(udid == "FOUND-UDID")
    }

    @Test("Given destination with id, when resolveBaseUDID called, then returns the given UDID")
    func resolveBaseUDIDReturnsDirectID() async throws {
        let json = SimulatorCommandMock.bootedDevicesJSON(udid: "DIRECT-UDID")
        let manager = SimulatorManager(launcher: SimulatorCommandMock(listOutput: json, cloneUDID: ""))

        let udid = try await manager.resolveBaseUDID(for: "platform=iOS Simulator,id=DIRECT-UDID")

        #expect(udid == "DIRECT-UDID")
    }

    @Test("Given destination with unknown name, when resolveBaseUDID called, then throws deviceNotFound")
    func resolveBaseUDIDThrowsForUnknownDevice() async throws {
        let emptyJSON = #"{"devices":{}}"#
        let manager = SimulatorManager(
            launcher: SimulatorCommandMock(listOutput: emptyJSON, cloneUDID: "")
        )

        await #expect(throws: SimulatorError.self) {
            try await manager.resolveBaseUDID(for: "platform=iOS Simulator,name=Unknown Device")
        }
    }

    @Test("Given booted device in JSON, when waitForBooted called, then returns on first poll without sleeping")
    func waitForBootedReturnsOnFirstPoll() async throws {
        let json = SimulatorCommandMock.bootedDevicesJSON(udid: "TEST-UDID")
        let manager = SimulatorManager(launcher: SimulatorCommandMock(listOutput: json, cloneUDID: ""))

        let start = Date()
        try await manager.waitForBooted(udid: "TEST-UDID")
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 0.4)
    }

    @Test("Given destination without platform= prefix, when requiresSimulatorPool called, then returns true")
    func requiresSimulatorPoolReturnsTrueForUnknownPlatform() {
        let result = SimulatorManager.requiresSimulatorPool(for: "name=My Device,OS=latest")
        #expect(result)
    }

    @Test("Given simulator never boots within max attempts, when waitForBooted called, then throws bootTimeout")
    func waitForBootedThrowsBootTimeoutWhenNeverBoots() async {
        let json = SimulatorCommandMock.bootedDevicesJSON(udid: "OTHER-UDID")
        let manager = SimulatorManager(launcher: SimulatorCommandMock(listOutput: json, cloneUDID: ""))

        await #expect(throws: SimulatorError.self) {
            try await manager.waitForBooted(udid: "TEST-UDID", maxAttempts: 1, sleepDuration: .zero)
        }
    }

    @Test("Given destination with neither id nor name, when resolveBaseUDID called, then throws deviceNotFound")
    func resolveBaseUDIDThrowsWhenNoIdOrName() async {
        let json = SimulatorCommandMock.bootedDevicesJSON(udid: "ANY-UDID")
        let manager = SimulatorManager(launcher: SimulatorCommandMock(listOutput: json, cloneUDID: ""))

        await #expect(throws: SimulatorError.self) {
            try await manager.resolveBaseUDID(for: "platform=iOS Simulator,arch=arm64")
        }
    }

    @Test("Given device list with non-matching name, when resolveBaseUDID called, then throws deviceNotFound")
    func resolveBaseUDIDThrowsWhenDeviceNameNotFoundInNonEmptyList() async {
        let json = SimulatorCommandMock.bootedDevicesJSON(udid: "OTHER-UDID", name: "iPhone 99")
        let manager = SimulatorManager(launcher: SimulatorCommandMock(listOutput: json, cloneUDID: ""))

        await #expect(throws: SimulatorError.self) {
            try await manager.resolveBaseUDID(for: "platform=iOS Simulator,name=iPhone 15")
        }
    }

    @Test("Given malformed JSON from simctl, when resolveBaseUDID with name called, then throws deviceNotFound")
    func resolveBaseUDIDThrowsForMalformedJSON() async {
        let manager = SimulatorManager(
            launcher: SimulatorCommandMock(listOutput: "not json", cloneUDID: "")
        )

        await #expect(throws: SimulatorError.self) {
            try await manager.resolveBaseUDID(for: "platform=iOS Simulator,name=iPhone 15")
        }
    }

    @Test("Given device not booted on first poll but booted on second, when waitForBooted called, then retries")
    func waitForBootedSleepsAndRetriesUntilBooted() async throws {
        let shutdown = #"{"devices":{"com.apple.runtime.iOS":[{"udid":"TEST-UDID","name":"M","state":"Shutdown"}]}}"#
        let booted = SimulatorCommandMock.bootedDevicesJSON(udid: "TEST-UDID")
        let manager = SimulatorManager(launcher: SequentialOutputMock(outputs: [shutdown, booted]))

        try await manager.waitForBooted(udid: "TEST-UDID", maxAttempts: 3, sleepDuration: .zero)
    }

    @Test("Given device never booted across attempts, when waitForBooted called, then throws bootTimeout with udid")
    func waitForBootedThrowsBootTimeoutWithCorrectUDID() async {
        let notBooted = #"{"devices":{"com.apple.runtime.iOS":[{"udid":"OTHER","name":"Mock","state":"Shutdown"}]}}"#
        let manager = SimulatorManager(
            launcher: SequentialOutputMock(outputs: [notBooted, notBooted, notBooted])
        )

        var threwBootTimeout = false
        do {
            try await manager.waitForBooted(udid: "TEST-UDID", maxAttempts: 2, sleepDuration: .zero)
        } catch SimulatorError.bootTimeout(udid: "TEST-UDID") {
            threwBootTimeout = true
        } catch {}

        #expect(threwBootTimeout)
    }
}

private actor SequentialOutputMock: ProcessLaunching {
    private let outputs: [String]
    private var callIndex = 0

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        additionalEnvironment: [String: String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        let output = outputs[min(callIndex, outputs.count - 1)]
        callIndex += 1
        return (0, output)
    }

}
