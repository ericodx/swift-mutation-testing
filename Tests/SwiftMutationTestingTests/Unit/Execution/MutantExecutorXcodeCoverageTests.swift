import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor — coverage map on Xcode")
struct MutantExecutorXcodeCoverageTests {
    @Test("Given a first Xcode run, when the baseline collects, then each mutant runs only the tests reaching it")
    func mutantsRunOnlyTheirReachingTests() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = XcodeCoverageLauncher(
            sitesByTest: ["S/a()": [fixture.site(9)], "S/b()": [fixture.site(9), fixture.site(40)]]
        )

        let results = try await fixture.execute(launcher: launcher)

        #expect(results.map(\.status) == [.survived, .survived])
        let baseline = try #require(await launcher.baselines.first)
        #expect(baseline.contains("-parallel-testing-enabled"))
        let environment = try #require(await launcher.baselineEnvironments.first)
        #expect(environment[SupportDeclarations.coverageRedirectVariable] == "1")
        #expect(environment[SupportDeclarations.coverageEnvironmentVariable]?.hasSuffix(".log") == true)
        let runs = await launcher.runs
        #expect(runs[0] == .init(mutantID: "m0", onlyTesting: ["AppTests/S/a()", "AppTests/S/b()"]))
        #expect(runs[1] == .init(mutantID: "m1", onlyTesting: ["AppTests/S/b()"]))
    }

    @Test("Given a site no test reaches on Xcode, when executed, then its mutant is noCoverage without a launch")
    func anUnreachedMutantIsNoCoverageWithoutRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = XcodeCoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])

        let results = try await fixture.execute(launcher: launcher)

        #expect(results.map(\.status) == [.survived, .noCoverage])
        #expect(await launcher.runs.map(\.mutantID) == ["m0"])
    }

    @Test("Given a site reached outside any test on Xcode, when executed, then its mutant runs the whole suite")
    func aSiteReachedOutsideEveryTestRunsTheWholeSuite() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = XcodeCoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]], outside: [fixture.site(40)])

        let results = try await fixture.execute(launcher: launcher)

        #expect(results.map(\.status) == [.survived, .survived])
        #expect(await launcher.runs.map(\.onlyTesting) == [["AppTests/S/a()"], []])
    }

    @Test("Given a map from an earlier Xcode run, when run again, then the baseline runs plainly and the map is used")
    func aStoredMapIsReusedWithoutCollecting() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = XcodeCoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])
        _ = try await fixture.execute(launcher: launcher)
        try fixture.forgetVerdicts()

        _ = try await fixture.execute(launcher: launcher)

        let environments = await launcher.baselineEnvironments
        #expect(environments.map { $0[SupportDeclarations.coverageEnvironmentVariable] != nil } == [true, false])
        #expect(await launcher.baselines.last?.contains("-parallel-testing-enabled") == false)
        #expect(await launcher.runs.map(\.onlyTesting) == [["AppTests/S/a()"], ["AppTests/S/a()"]])
    }

    @Test("Given a test target on Xcode, when the mutants run, then only its reaching tests are selected")
    func aTestTargetKeepsOnlyItsTests() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = XcodeCoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9), fixture.site(40)]])

        _ = try await fixture.execute(launcher: launcher, testTarget: "AppTests")

        #expect(await launcher.baselines.first?.contains("AppTests") == true)
        #expect(await launcher.runs.map(\.onlyTesting) == [["AppTests/S/a()"], ["AppTests/S/a()"]])
    }

    @Test("Given --no-cache on Xcode, when executed, then nothing is collected and every mutant runs as before")
    func noCacheRunsAsBefore() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let launcher = XcodeCoverageLauncher(sitesByTest: ["S/a()": [fixture.site(9)]])

        let results = try await fixture.execute(launcher: launcher, noCache: true)

        #expect(results.map(\.status) == [.survived, .survived])
        #expect(await launcher.baselineEnvironments.first?[SupportDeclarations.coverageEnvironmentVariable] == nil)
        #expect(await launcher.runs.map(\.onlyTesting) == [[], []])
    }

    // MARK: - Fixture

    private struct Fixture {
        let directory: URL
        let sourceFile: URL

        init() throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            sourceFile = directory.appendingPathComponent("Sources/App/A.swift")
            try FileManager.default.createDirectory(
                at: sourceFile.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "func f() { let x = true }\nfunc g() { let y = true }".write(
                to: sourceFile, atomically: true, encoding: .utf8
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

        func execute(
            launcher: XcodeCoverageLauncher, testTarget: String? = nil, noCache: Bool = false
        ) async throws -> [ExecutionResult] {
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
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: mutants
            )
            input.sourceHashes = ["Sources/App/A.swift": "h1"]
            let configuration = makeRunnerConfiguration(
                projectPath: directory.path, testTarget: testTarget, noCache: noCache
            )
            return try await MutantExecutor(configuration: configuration, launcher: launcher).execute(input)
        }
    }
}
