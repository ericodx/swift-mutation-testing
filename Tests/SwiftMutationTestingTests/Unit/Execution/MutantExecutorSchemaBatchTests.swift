import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor schema batches")
struct MutantExecutorSchemaBatchTests {
    @Test("Given a function over the limit, when the suite crashes on the whole schema, then it is built in batches")
    func aFunctionOverTheLimitIsBuiltInBatchesAfterTheSuiteCrashes() async throws {
        let fixture = try Fixture(mutantCount: SchemaBatches.mutantsPerFunction + 1)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher(crashesAgainstSchemasOver: SchemaBatches.mutantsPerFunction)
        let reporter = MockProgressReporter()

        let results = try await fixture.run(launcher: launcher, reporter: reporter)

        let schemas = await launcher.builtSchemas
        #expect(schemas.map { $0.components(separatedBy: "case \"").count - 1 } == [17, 16, 1])
        #expect(Set(results.map(\.descriptor.id)) == Set(fixture.input.mutants.map(\.id)))
        #expect(await launcher.builtMutatedSources == 0)
        let batches = await reporter.events.compactMap { event -> Int? in
            guard case .schemaBatchStarted(let index, let count, _) = event, count == 2 else { return nil }
            return index
        }
        #expect(batches == [1, 2])
        let splitting = await reporter.events.compactMap { event -> Bool? in
            guard case .schemaSuiteFailed(let splitting) = event else { return nil }
            return splitting
        }
        #expect(splitting == [true])
    }

    @Test("Given a function over the batch limit, when the suite passes on the whole schema, then it is built once")
    func aFunctionOverTheLimitBuildsOnceWhenTheSuitePasses() async throws {
        let fixture = try Fixture(mutantCount: SchemaBatches.mutantsPerFunction + 1)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher()
        let reporter = MockProgressReporter()

        _ = try await fixture.run(launcher: launcher, reporter: reporter)

        #expect(await launcher.builtSchemas.count == 1)
        let reportedBatch = await reporter.events.contains { event in
            if case .schemaBatchStarted = event { return true }
            return false
        }
        #expect(!reportedBatch)
    }

    @Test("Given the suite also crashes on every batch, when run, then the batches' mutants are built one by one")
    func batchesThatCrashTooFallBackToOneByOne() async throws {
        let fixture = try Fixture(mutantCount: SchemaBatches.mutantsPerFunction + 1)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher(crashesAgainstSchemasOver: 0)
        let reporter = MockProgressReporter()

        let results = try await fixture.run(launcher: launcher, reporter: reporter)

        #expect(results.count == fixture.input.mutants.count)
        #expect(await launcher.builtMutatedSources == fixture.input.mutants.count)
        let splitting = await reporter.events.compactMap { event -> Bool? in
            guard case .schemaSuiteFailed(let splitting) = event else { return nil }
            return splitting
        }
        #expect(splitting == [true, false, false])
    }

    @Test("Given every function within the limit, when run, then the schema is built once and no batch is reported")
    func functionsWithinTheLimitBuildOnce() async throws {
        let fixture = try Fixture(mutantCount: 2)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher()
        let reporter = MockProgressReporter()

        _ = try await fixture.run(launcher: launcher, reporter: reporter)

        #expect(await launcher.builtSchemas.count == 1)
        let reportedBatch = await reporter.events.contains { event in
            if case .schemaBatchStarted = event { return true }
            return false
        }
        #expect(!reportedBatch)
    }

    @Test("Given the unmutated suite crashes only against the schema, when run, then its mutants are built one by one")
    func aSuiteThatCrashesOnlyAgainstTheSchemaFallsBack() async throws {
        let fixture = try Fixture(mutantCount: 2)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher(crashesAgainstSchemasOver: 0)
        let reporter = MockProgressReporter()

        let results = try await fixture.run(launcher: launcher, reporter: reporter)

        #expect(results.map(\.status) == [.survived, .survived])
        #expect(await launcher.builtMutatedSources == 2)
        let splitting = await reporter.events.compactMap { event -> Bool? in
            guard case .schemaSuiteFailed(let splitting) = event else { return nil }
            return splitting
        }
        #expect(splitting == [false])
    }

    @Test("Given the suite fails only against the schema, when run, then the check and the mutants share its sandbox")
    func theUnmutatedSuiteCheckAndTheMutantsRunInTheSchemaSandbox() async throws {
        let fixture = try Fixture(mutantCount: 2)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher(crashesAgainstSchemasOver: 0)

        _ = try await fixture.run(launcher: launcher, reporter: MockProgressReporter())

        #expect(await launcher.builtUnmutatedSources == 2)
        #expect(await launcher.buildRoots.count == 1)
    }

    @Test("Given the unmutated suite also crashes without the schema, when run, then the run stops")
    func aSuiteThatCrashesEverywhereStopsTheRun() async throws {
        let fixture = try Fixture(mutantCount: 2)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher(crashesAgainstSchemasOver: 0, crashesUnmutated: true)

        await #expect(throws: BaselineError.self) {
            _ = try await fixture.run(launcher: launcher, reporter: MockProgressReporter())
        }
    }

    @Test("Given the unmutated project no longer builds after the schema suite fails, when run, then the run stops")
    func anUnmutatedBuildFailureAfterTheSchemaSuiteFailsStopsTheRun() async throws {
        let fixture = try Fixture(mutantCount: 2)
        defer { fixture.cleanUp() }
        let launcher = SchemaSuiteLauncher(crashesAgainstSchemasOver: 0, unmutatedBuildOutput: "Validate plug-in")

        await #expect(throws: BaselineError.buildFailed(output: "Validate plug-in")) {
            _ = try await fixture.run(launcher: launcher, reporter: MockProgressReporter())
        }
    }

    // MARK: - Private

    private struct Fixture {
        let directory: URL
        let input: RunnerInput

        init(mutantCount: Int) throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            let file = directory.appendingPathComponent("Foo.swift")
            let source = "func f() { " + (0 ..< mutantCount).map { "let v\($0) = true" }.joined(separator: "; ") + " }"
            try source.write(to: file, atomically: true, encoding: .utf8)

            var mutants: [MutantDescriptor] = []
            var searchStart = source.startIndex
            while let range = source.range(of: "true", range: searchStart ..< source.endIndex) {
                let offset = source.utf8.distance(from: source.startIndex, to: range.lowerBound)
                mutants.append(
                    makeMutantDescriptor(
                        id: MutantID.make(index: mutants.count), filePath: file.path, utf8Offset: offset,
                        originalText: "true", mutatedText: "false", replacementKind: .booleanLiteral,
                        isSchematizable: true
                    )
                )
                searchStart = range.upperBound
            }

            let schema = try #require(SchemaNarrower.regeneratedSchema(originalPath: file.path, keeping: mutants))
            input = makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [SchematizedFile(originalPath: file.path, schematizedContent: schema)],
                mutants: mutants
            )
        }

        func run(launcher: SchemaSuiteLauncher, reporter: MockProgressReporter) async throws -> [ExecutionResult] {
            var environment = MutantExecutor.Environment()
            environment.reporter = reporter
            return try await MutantExecutor(
                configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm, noCache: true),
                launcher: launcher,
                environment: environment
            ).execute(input)
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }
    }
}

private actor SchemaSuiteLauncher: ProcessLaunching {
    private let crashesAgainstSchemasOver: Int?
    private let crashesUnmutated: Bool
    private let unmutatedBuildOutput: String?
    private(set) var builtSchemas: [String] = []
    private(set) var builtMutatedSources = 0
    private(set) var builtUnmutatedSources = 0
    private(set) var buildRoots: Set<String> = []

    init(crashesAgainstSchemasOver: Int? = nil, crashesUnmutated: Bool = false, unmutatedBuildOutput: String? = nil) {
        self.crashesAgainstSchemasOver = crashesAgainstSchemasOver
        self.crashesUnmutated = crashesUnmutated
        self.unmutatedBuildOutput = unmutatedBuildOutput
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(_ request: ProcessRequest) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()
        let source =
            (try? String(contentsOf: request.workingDirectoryURL.appendingPathComponent("Foo.swift"), encoding: .utf8))
            ?? ""
        let caseCount = source.components(separatedBy: "case \"\(MutantID.prefix)").count - 1
        let isSchema = caseCount > 0

        if request.executableURL.lastPathComponent == "swift", request.arguments.first == "build" {
            buildRoots.insert(request.workingDirectoryURL.path)
            if isSchema {
                builtSchemas.append(source)
            } else if source.contains("false") {
                builtMutatedSources += 1
            } else if let unmutatedBuildOutput {
                return (1, unmutatedBuildOutput)
            } else {
                builtUnmutatedSources += 1
            }
            return (0, "")
        }

        let active =
            request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"]
            ?? request.environment?["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
        let crashes =
            active.isEmpty
            && (isSchema
                ? caseCount > (crashesAgainstSchemasOver ?? .max)
                : crashesUnmutated && !source.contains("false"))
        return crashes ? (1, "") : (0, "")
    }
}
