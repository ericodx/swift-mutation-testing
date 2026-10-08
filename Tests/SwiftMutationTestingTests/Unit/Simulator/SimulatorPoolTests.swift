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

    @Test("Given a destination with no platform, when the pool is set up, then slots fall back to the iOS Simulator")
    func aDestinationWithoutAPlatformFallsBackToTheSimulator() async throws {
        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 1,
            destination: "id=BASE-UDID",
            launcher: SimulatorCommandMock(
                listOutput: SimulatorCommandMock.bootedDevicesJSON(udid: "CLONE-1"), cloneUDID: "CLONE-1"
            )
        )

        try await pool.setUp()
        let slot = try await pool.acquire()
        await pool.release(slot)

        #expect(slot.destination == "platform=iOS Simulator,id=CLONE-1")
    }

    @Test("Given a request that is no longer pending, when it is cancelled, then the pool is untouched")
    func cancellingARequestThatIsNotPendingChangesNothing() async throws {
        let pool = makeSimulatorPool()
        try await pool.setUp()

        await pool.cancelPending(id: UUID())

        let slot = try await pool.acquire()
        await pool.release(slot)
    }

    @Test("Given the second of three clones fails, when setUp called, then the clones that succeeded are deleted")
    func aFailedCloneDeletesTheClonesThatSucceeded() async throws {
        let mock = SimulatorCloneFailureMock(failingCloneIndices: [1])
        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 3,
            destination: "platform=iOS Simulator,name=iPhone 15",
            launcher: mock
        )

        await #expect(throws: SimulatorError.self) {
            try await pool.setUp()
        }

        #expect(mock.deletedUDIDs == ["CLONE-0", "CLONE-2"])
    }

    @Test("Given every clone succeeds but booting fails, when setUp called, then every clone is deleted")
    func aFailedBootDeletesEveryClone() async throws {
        let mock = SimulatorCloneFailureMock(bootFails: true)
        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 2,
            destination: "platform=iOS Simulator,name=iPhone 15",
            launcher: mock
        )

        await #expect(throws: SimulatorError.self) {
            try await pool.setUp()
        }

        #expect(mock.deletedUDIDs == ["CLONE-0", "CLONE-1"])
    }

    @Test("Given a device list, when orphaned clones are looked for, then only clones of runs that are gone are named")
    func orphanedClonesAreFoundInTheDeviceList() {
        let list = """
            {"devices":{"com.apple.runtime.iOS":[
              {"udid":"A","name":"XMR-111-1a2b3c4d-0","state":"Booted"},
              {"udid":"B","name":"XMR-222-1a2b3c4d-0","state":"Shutdown"},
              {"udid":"C","name":"iPhone 16","state":"Shutdown"},
              {"udid":"D","name":"XMR-9f8e7d6c-1","state":"Shutdown"}
            ]}}
            """

        let orphans = SimulatorPool.orphanedClones(in: list, isAlive: { $0 == 222 })

        #expect(orphans == ["A", "D"])
    }

    @Test("Given output that is not a device list, when orphaned clones are looked for, then none are named")
    func unreadableListNamesNoOrphan() {
        #expect(SimulatorPool.orphanedClones(in: "not json", isAlive: { _ in false }).isEmpty)
    }

    @Test("Given a clone left by a run that is gone, when a pool is set up, then that clone is deleted")
    func setUpDeletesTheClonesOfDeadRuns() async throws {
        let list = """
            {"devices":{"com.apple.runtime.iOS":[{"udid":"ORPHAN","name":"XMR-1a2b3c4d-0","state":"Shutdown"}]}}
            """
        let mock = SimulatorCloneFailureMock(bootFails: true, listOutput: list)
        let pool = SimulatorPool(
            baseUDID: "BASE-UDID",
            size: 1,
            destination: "platform=iOS Simulator,name=iPhone 15",
            launcher: mock
        )

        await #expect(throws: SimulatorError.self) {
            try await pool.setUp()
        }

        #expect(mock.deletedUDIDs == ["CLONE-0", "ORPHAN"])
    }

    @Test("Given a clone named after a run that has exited, when a pool is set up, then that clone is deleted")
    func setUpDeletesTheCloneOfAnExitedRun() async throws {
        let exited = Process()
        exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try exited.run()
        exited.waitUntilExit()
        let name = CloneName.make(session: "1a2b3c4d", index: 0, pid: exited.processIdentifier)
        let list = """
            {"devices":{"com.apple.runtime.iOS":[{"udid":"GONE","name":"\(name)","state":"Shutdown"}]}}
            """
        let mock = SimulatorCloneFailureMock(bootFails: true, listOutput: list)
        let pool = SimulatorPool(
            baseUDID: "BASE-UDID", size: 1, destination: "platform=iOS Simulator,name=iPhone 15", launcher: mock
        )

        await #expect(throws: SimulatorError.self) {
            try await pool.setUp()
        }

        #expect(mock.deletedUDIDs.contains("GONE"))
    }
}
