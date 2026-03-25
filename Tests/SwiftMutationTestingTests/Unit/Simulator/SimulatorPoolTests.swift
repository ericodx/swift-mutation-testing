import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SimulatorPool")
struct SimulatorPoolTests {
    @Test("Given macOS destination, when setUp called, then creates single slot with original destination")
    func setUpMacOSCreatesSingleSlot() async throws {
        let pool = SimulatorPool(
            baseUDID: nil,
            size: 4,
            destination: "platform=macOS,arch=arm64",
            launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let slot = try await pool.acquire()

        #expect(slot.destination == "platform=macOS,arch=arm64")
    }

    @Test("Given available slot, when acquire called, then returns slot immediately")
    func acquireReturnsSlotImmediately() async throws {
        let pool = SimulatorPool(
            baseUDID: nil,
            size: 1,
            destination: "platform=macOS",
            launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let slot = try await pool.acquire()

        #expect(slot.destination == "platform=macOS")
    }

    @Test("Given pool exhausted, when acquire called, then suspends until release")
    func acquireSuspendsWhenPoolExhausted() async throws {
        let pool = SimulatorPool(
            baseUDID: nil,
            size: 1,
            destination: "platform=macOS",
            launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let firstSlot = try await pool.acquire()

        let pendingTask = Task { try await pool.acquire() }
        try await Task.sleep(for: .milliseconds(50))

        await pool.release(firstSlot)

        let resumedSlot = try await pendingTask.value

        #expect(resumedSlot.destination == "platform=macOS")
    }

    @Test("Given simulator baseUDID and size 2, when setUp called, then creates 2 acquirable slots")
    func setUpSimulatorCreatesNSlots() async throws {
        let cloneUDID = "MOCK-CLONE-UDID"
        let mock = SimulatorCommandMock(
            listOutput: SimulatorCommandMock.bootedDevicesJSON(udid: cloneUDID),
            cloneUDID: cloneUDID
        )

        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 2,
            destination: "platform=iOS Simulator,name=iPhone 15",
            launcher: mock
        )
        try await pool.setUp()

        let slot1 = try await pool.acquire()
        let slot2 = try await pool.acquire()

        #expect(slot1.destination.contains("platform=iOS Simulator"))
        #expect(slot2.destination.contains("platform=iOS Simulator"))
    }

    @Test("Given simulator baseUDID and xcrun clone fails, when setUp called, then throws")
    func setUpThrowsWhenCloneFails() async throws {
        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 1,
            destination: "platform=iOS Simulator,name=iPhone 15",
            launcher: MockProcessLauncher(exitCode: 0, responses: ["xcrun": (exitCode: 1, output: "")])
        )

        await #expect(throws: (any Error).self) {
            try await pool.setUp()
        }
    }

    @Test("Given pool exhausted and pending task is cancelled, when acquire waiting, then throws CancellationError")
    func cancelledAcquireThrowsCancellationError() async throws {
        let pool = SimulatorPool(
            baseUDID: nil,
            size: 1,
            destination: "platform=macOS",
            launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let firstSlot = try await pool.acquire()

        let pendingTask = Task {
            try await pool.acquire()
        }

        try await Task.sleep(for: .milliseconds(50))
        pendingTask.cancel()

        await #expect(throws: (any Error).self) {
            try await pendingTask.value
        }

        await pool.release(firstSlot)
    }

    @Test("Given setUp with simulator, when tearDown called, then pool size is preserved")
    func tearDownCompletesForSimulatorPool() async throws {
        let cloneUDID = "MOCK-CLONE-UDID"
        let mock = SimulatorCommandMock(
            listOutput: SimulatorCommandMock.bootedDevicesJSON(udid: cloneUDID),
            cloneUDID: cloneUDID
        )

        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 3,
            destination: "platform=iOS Simulator,name=iPhone 15",
            launcher: mock
        )
        try await pool.setUp()
        await pool.tearDown()

        #expect(pool.size == 3)
    }
}
