import Testing

@testable import SwiftMutationTesting

@Suite("DiscoveryPipeline")
struct DiscoveryPipelineTests {
    private let pipeline = DiscoveryPipeline()

    @Test("Given valid sources path, when run, then returns populated RunnerInput")
    func validSourcesProducesRunnerInput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)

        let input = makeInput(projectPath: dir.path, sourcesPath: dir.path)
        let result = try await pipeline.run(input: input)

        #expect(result.projectPath == dir.path)
        #expect(!result.mutants.isEmpty)
    }

    @Test("Given non-existent sources path, when run, then throws")
    func nonExistentSourcesPathThrows() async {
        let input = makeInput(projectPath: "/nonexistent", sourcesPath: "/nonexistent/does/not/exist")

        await #expect(throws: (any Error).self) {
            _ = try await pipeline.run(input: input)
        }
    }

    @Test("Given specific operator list, when run, then only those operators produce mutants")
    func specificOperatorsAreRespected() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)

        let input = makeInput(sourcesPath: dir.path, operators: ["BooleanLiteralReplacement"])
        let result = try await pipeline.run(input: input)

        #expect(result.mutants.allSatisfy { $0.operatorIdentifier == "BooleanLiteralReplacement" })
    }

    @Test("Given source with function body mutation, when run, then produces schematized file")
    func schematizableMutationProducesSchematizedFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)

        let input = makeInput(sourcesPath: dir.path, operators: ["BooleanLiteralReplacement"])
        let result = try await pipeline.run(input: input)

        #expect(!result.schematizedFiles.isEmpty)
        #expect(result.supportFileContent.contains("__swiftMutationTestingID"))
        #expect(result.supportFileContent.contains("__SWIFT_MUTATION_TESTING_ACTIVE"))
    }

    @Test("Given RunnerInput contract, when run, then all fields map from DiscoveryInput")
    func runnerInputContractFieldsMapCorrectly() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("func f() { let x = true }", named: "Source.swift", in: dir)

        let input = DiscoveryInput(
            projectPath: "/project",
            scheme: "MyScheme",
            destination: "platform=macOS",
            timeout: 120,
            concurrency: 8,
            noCache: true,
            sourcesPath: dir.path,
            excludePatterns: [],
            operators: []
        )
        let result = try await pipeline.run(input: input)

        #expect(result.projectPath == "/project")
        #expect(result.scheme == "MyScheme")
        #expect(result.destination == "platform=macOS")
        #expect(result.timeout == 120)
        #expect(result.concurrency == 8)
        #expect(result.noCache == true)
    }

    @Test("Given empty operators list, when run, then all default operators are used")
    func emptyOperatorsListUsesAllDefaults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write(
            "func f() { let x = true; let y = 1 + 2 }",
            named: "Source.swift",
            in: dir
        )

        let input = makeInput(sourcesPath: dir.path, operators: [])
        let result = try await pipeline.run(input: input)

        let identifiers = Set(result.mutants.map { $0.operatorIdentifier })
        #expect(identifiers.count > 1)
    }

    @Test("Given excluded pattern, when run, then matching files are not mutated")
    func excludedPatternFilesAreNotMutated() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileHelpers.write("func f() { let x = true }", named: "Generated.swift", in: dir)

        let input = makeInput(sourcesPath: dir.path, excludePatterns: ["Generated.swift"])
        let result = try await pipeline.run(input: input)

        #expect(result.mutants.isEmpty)
        #expect(result.schematizedFiles.isEmpty)
    }
}

extension DiscoveryPipelineTests {
    private func makeInput(
        projectPath: String = "/project",
        sourcesPath: String,
        excludePatterns: [String] = [],
        operators: [String] = []
    ) -> DiscoveryInput {
        DiscoveryInput(
            projectPath: projectPath,
            scheme: "Scheme",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 4,
            noCache: false,
            sourcesPath: sourcesPath,
            excludePatterns: excludePatterns,
            operators: operators
        )
    }
}
