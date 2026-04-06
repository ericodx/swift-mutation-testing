@testable import SwiftMutationTesting

func makeSimulatorPool(launcher: any ProcessLaunching = MockProcessLauncher(exitCode: 0)) -> SimulatorPool {
    SimulatorPool(
        baseUDID: nil,
        size: 1,
        destination: "platform=macOS",
        launcher: launcher
    )
}
