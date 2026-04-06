import Foundation

@testable import SwiftMutationTesting

func makeIncompatibleMutantExecutor(
    in dir: URL,
    exitCode: Int32
) -> IncompatibleMutantExecutor {
    IncompatibleMutantExecutor(
        deps: makeExecutionDeps(
            launcher: MockProcessLauncher(exitCode: exitCode),
            cacheStorePath: dir.appendingPathComponent("cache.json").path,
            total: 3
        ),
        sandboxFactory: SandboxFactory()
    )
}

func makeIncompatibleMutantExecutorSPM(
    in dir: URL,
    launcher: any ProcessLaunching
) -> IncompatibleMutantExecutor {
    IncompatibleMutantExecutor(
        deps: makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        ),
        sandboxFactory: SandboxFactory()
    )
}
