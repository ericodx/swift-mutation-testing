import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor — coverage map")
struct MutantExecutorCoverageMapTests {
    @Test("Given a first run, when the baseline is collected, then each mutant runs only the tests reaching it")
    func mutantsRunOnlyTheirReachingTests() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = CoverageLauncher(
            sitesByTest: ["S/a()": [fixture.site(9)], "S/b()": [fixture.site(9), fixture.site(40)]], killers: ["S/b()"]
        )

        let results = try await fixture.execute(launcher: launcher)

        #expect(results.map(\.status) == [.killed(by: "S/b()"), .killed(by: "S/b()")])
        #expect(await launcher.baselines == [true])
        let filters = await launcher.runs.map(\.filters)
        #expect(filters[0] == ["^CoreTests\\.S\\/a\\(\\)/", "^CoreTests\\.S\\/b\\(\\)/"])
        #expect(filters[1] == ["^CoreTests\\.S\\/b\\(\\)/"])
    }

    @Test("Given a site no test reaches, when executed, then its mutant is noCoverage without a test run")
    func anUnreachedMutantIsNoCoverageWithoutRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = CoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])

        let results = try await fixture.execute(launcher: launcher)

        #expect(results.map(\.status) == [.survived, .noCoverage])
        #expect(await launcher.runs.map(\.mutantID) == ["m0"])
    }

    @Test("Given a site reached outside any test, when executed, then its mutant runs as before, unfiltered")
    func aSiteReachedOutsideEveryTestRunsTheWholeSuite() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = CoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]], outside: [fixture.site(40)])

        let results = try await fixture.execute(launcher: launcher)

        #expect(results.map(\.status) == [.survived, .survived])
        #expect(await launcher.runs.map(\.filters) == [["^CoreTests\\.S\\/a\\(\\)/"], []])
    }

    @Test("Given a map from an earlier run and nothing changed, when executed, then the baseline is not collected")
    func aStoredMapSparesTheCollection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = CoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])
        _ = try await fixture.execute(launcher: launcher)
        let metadataURL = fixture.directory.appendingPathComponent(".swift-mutation-testing-cache/metadata.json")
        let metadata = try JSONDecoder().decode(CacheStore.CacheMetadata.self, from: Data(contentsOf: metadataURL))
        #expect(metadata.coverage?.sites[fixture.site(9)]?.map(\.id) == ["CoreTests.S/a()"])
        try fixture.forgetVerdicts()

        _ = try await fixture.execute(launcher: launcher)

        #expect(await launcher.baselines == [true, false])
        #expect(await launcher.runs.map(\.filters) == [["^CoreTests\\.S\\/a\\(\\)/"], ["^CoreTests\\.S\\/a\\(\\)/"]])
    }

    @Test("Given a map from an earlier run, when a test file changed, then the baseline is collected again")
    func aChangedTestFileCollectsAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = CoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])
        _ = try await fixture.execute(launcher: launcher)
        try "@Suite struct S { @Test func c() {} }".write(to: fixture.testFile, atomically: true, encoding: .utf8)

        _ = try await fixture.execute(launcher: launcher)

        #expect(await launcher.baselines == [true, true])
    }

    @Test("Given --no-cache, when executed, then nothing is collected and every mutant runs as before")
    func noCacheRunsAsBefore() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = CoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])

        let results = try await fixture.execute(launcher: launcher, noCache: true)

        #expect(results.map(\.status) == [.survived, .survived])
        #expect(await launcher.baselines == [false])
        #expect(await launcher.runs.map(\.filters) == [[], []])
    }

    // MARK: - Fixture

    private struct Fixture {
        let directory: URL
        let sourceFile: URL
        let testFile: URL

        init() throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            sourceFile = directory.appendingPathComponent("Sources/Core/A.swift")
            testFile = directory.appendingPathComponent("Tests/CoreTests/STests.swift")
            for file in [sourceFile, testFile] {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
            }
            try "func f() { let x = true }\nfunc g() { let y = true }".write(
                to: sourceFile, atomically: true, encoding: .utf8
            )
            try "@Suite struct S { @Test func a() {} @Test func b() {} }".write(
                to: testFile, atomically: true, encoding: .utf8
            )
        }

        func site(_ bodyStart: Int) -> String {
            TestCoverage.key(suffix: SupportDeclarations.suffix(for: sourceFile.path), site: bodyStart)
        }

        func forgetVerdicts() throws {
            let cache = directory.appendingPathComponent(".swift-mutation-testing-cache")
            try FileManager.default.removeItem(at: cache.appendingPathComponent("results.json"))
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }

        func execute(launcher: CoverageLauncher, noCache: Bool = false) async throws -> [ExecutionResult] {
            let mutants = [
                makeMutantDescriptor(
                    id: "m0", filePath: sourceFile.path, utf8Offset: 19, isSchematizable: true, functionBodyStart: 9
                ),
                makeMutantDescriptor(
                    id: "m1", filePath: sourceFile.path, utf8Offset: 45, isSchematizable: true, functionBodyStart: 40
                ),
            ]
            var input = makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: mutants
            )
            input.sourceHashes = ["Sources/Core/A.swift": "h1"]
            let configuration = makeRunnerConfiguration(
                projectPath: directory.path, projectType: .spm, noCache: noCache
            )
            return try await MutantExecutor(configuration: configuration, launcher: launcher).execute(input)
        }
    }
}
