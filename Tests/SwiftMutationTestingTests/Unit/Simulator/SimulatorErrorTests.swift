import Testing

@testable import SwiftMutationTesting

@Suite("SimulatorError")
struct SimulatorErrorTests {
    @Test("Given deviceNotFound, when errorDescription accessed, then includes destination")
    func deviceNotFound() {
        let error = SimulatorError.deviceNotFound(destination: "platform=iOS Simulator")
        #expect(error.errorDescription?.contains("platform=iOS Simulator") == true)
    }

    @Test("Given bootTimeout, when errorDescription accessed, then includes udid")
    func bootTimeout() {
        let error = SimulatorError.bootTimeout(udid: "ABC-123")
        #expect(error.errorDescription?.contains("ABC-123") == true)
    }

    @Test("Given cloneFailed, when errorDescription accessed, then includes udid")
    func cloneFailed() {
        let error = SimulatorError.cloneFailed(udid: "DEF-456")
        #expect(error.errorDescription?.contains("DEF-456") == true)
    }
}
