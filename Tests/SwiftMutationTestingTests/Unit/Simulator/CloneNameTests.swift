import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("CloneName")
struct CloneNameTests {
    @Test("Given a session and an index, when a clone is named, then the name carries the pid, session and index")
    func theNameCarriesThePid() {
        #expect(CloneName.make(session: "1a2b3c4d", index: 2, pid: 4242) == "XMR-4242-1a2b3c4d-2")
    }

    @Test("Given a clone whose owner is gone, when checked, then it is orphaned")
    func aCloneOfADeadRunIsOrphaned() {
        #expect(CloneName.isOrphaned("XMR-4242-1a2b3c4d-0", isAlive: { _ in false }))
    }

    @Test("Given a clone whose owner is still running, when checked, then it is kept")
    func aCloneOfALiveRunIsKept() {
        #expect(!CloneName.isOrphaned("XMR-4242-1a2b3c4d-0", isAlive: { _ in true }))
    }

    @Test("Given a clone named before the pid was in the name, when checked, then it is orphaned")
    func aLegacyCloneIsOrphaned() {
        #expect(CloneName.isOrphaned("XMR-1a2b3c4d-3", isAlive: { _ in true }))
    }

    @Test(
        "Given a device that is not one of the tool's clones, when checked, then it is kept",
        arguments: [
            "iPhone 16", "XMR-phone", "XMR-4242-notahexid-0", "XMR-0-1a2b3c4d-0", "XMR-4242-1a2b3c4d-x", "xmr-1-a",
        ]
    )
    func anotherDeviceIsKept(name: String) {
        #expect(!CloneName.isOrphaned(name, isAlive: { _ in false }))
    }
}
