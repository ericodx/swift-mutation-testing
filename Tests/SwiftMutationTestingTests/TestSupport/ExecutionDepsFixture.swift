import Foundation

@testable import SwiftMutationTesting

func makeExecutionDeps(
    launcher: any ProcessLaunching = MockProcessLauncher(exitCode: 0),
    cacheStorePath: String = "/tmp/cache.json",
    reporter: any ProgressReporter = MockProgressReporter(),
    total: Int = 1,
    testFilePaths: [String] = []
) -> ExecutionDeps {
    ExecutionDeps(
        launcher: launcher,
        cacheStore: CacheStore(storePath: cacheStorePath),
        reporter: reporter,
        counter: MutationCounter(total: total),
        killerTestFileResolver: KillerTestFileResolver(testFilePaths: testFilePaths)
    )
}
