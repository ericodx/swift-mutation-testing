import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SimulatorManager")
struct SimulatorManagerTests {
    @Test("Given iOS Simulator destination, when requiresSimulatorPool called, then returns true")
    func requiresSimulatorPoolReturnsTrueForIOSSimulator() {
        let result = SimulatorManager.requiresSimulatorPool(for: "platform=iOS Simulator,name=iPhone 15")

        #expect(result == true)
    }

    @Test("Given macOS destination, when requiresSimulatorPool called, then returns false")
    func requiresSimulatorPoolReturnsFalseForMacOS() {
        let result = SimulatorManager.requiresSimulatorPool(for: "platform=macOS,arch=arm64")

        #expect(result == false)
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
}
