import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite(.tags(.integration))
struct DiscoveryPipelineIntegrationTests {
    private let pipeline = DiscoveryPipeline()

    @Test("Given CalcApp fixture, when run, then mutants are discovered across all source files")
    func discoversAllSourceFiles() async throws {
        let input = makeInput()
        let result = try await pipeline.run(input: input)

        let files = Set(result.mutants.map { URL(fileURLWithPath: $0.filePath).lastPathComponent })
        #expect(files.contains("Calculator.swift"))
        #expect(files.contains("Validator.swift"))
        #expect(files.contains("Logic.swift"))
    }

    @Test("Given CalcApp fixture, when run, then schematized content never declares __swiftMutationTestingID")
    func schematizedContentDoesNotDeclareIDVariable() async throws {
        let input = makeInput()
        let result = try await pipeline.run(input: input)

        for file in result.schematizedFiles {
            #expect(!file.schematizedContent.contains("var __swiftMutationTestingID"))
        }

        #expect(result.supportFileContent.contains("__swiftMutationTestingID"))
        #expect(result.supportFileContent.contains("__SWIFT_MUTATION_TESTING_ACTIVE"))
    }

    @Test("Given CalcApp fixture, when run, then function-body mutations produce schematized files")
    func functionBodyMutationsAreSchematized() async throws {
        let input = makeInput()
        let result = try await pipeline.run(input: input)

        #expect(!result.schematizedFiles.isEmpty)
        let allContent = result.schematizedFiles.map { $0.schematizedContent }.joined()
        #expect(allContent.contains("switch __swiftMutationTestingID"))
        #expect(allContent.contains("swift-mutation-testing_"))
    }

    @Test("Given CalcApp fixture with excludePatterns for Logic.swift, when run, then Logic.swift has no mutants")
    func excludePatternsExcludesMatchingFiles() async throws {
        let input = makeInput(excludePatterns: ["Logic.swift"])
        let result = try await pipeline.run(input: input)

        let logicMutants = result.mutants.filter {
            URL(fileURLWithPath: $0.filePath).lastPathComponent == "Logic.swift"
        }
        #expect(logicMutants.isEmpty)
    }

    @Test("Given CalcApp fixture with specific operators, when run, then only those operators produce mutants")
    func specificOperatorsAreRespected() async throws {
        let input = makeInput(operators: ["RelationalOperatorReplacement"])
        let result = try await pipeline.run(input: input)

        #expect(!result.mutants.isEmpty)
        #expect(
            result.mutants.allSatisfy { $0.operatorIdentifier == "RelationalOperatorReplacement" }
        )
    }

    @Test("Given source with @SwiftMutationTestingDisabled function, when run, then no mutants from suppressed scope")
    func suppressedFunctionProducesNoMutants() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = """
            @SwiftMutationTestingDisabled
            func suppressed(_ a: Int, _ b: Int) -> Int { a + b }

            func active(_ a: Int, _ b: Int) -> Int { a + b }
            """
        try source.write(to: dir.appendingPathComponent("Mixed.swift"), atomically: true, encoding: .utf8)

        let input = DiscoveryInput(
            projectPath: dir.path,
            scheme: "Scheme",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 1,
            noCache: false,
            sourcesPath: dir.path,
            excludePatterns: [],
            operators: ["ArithmeticOperatorReplacement"]
        )
        let result = try await pipeline.run(input: input)

        #expect(result.mutants.count == 1)
        #expect(result.mutants[0].originalText == "+")
    }

    @Test("Given CalcApp fixture, when run, then __SMTSupport.swift produces no mutants")
    func smtSupportFileProducesNoMutants() async throws {
        let input = makeInput()
        let result = try await pipeline.run(input: input)

        let supportMutants = result.mutants.filter {
            URL(fileURLWithPath: $0.filePath).lastPathComponent == "__SMTSupport.swift"
        }
        #expect(supportMutants.isEmpty)
    }

    @Test("Given CalcApp fixture, when run, then mutant IDs use correct sequential format")
    func mutantIDsAreSequentiallyIndexed() async throws {
        let input = makeInput()
        let result = try await pipeline.run(input: input)

        let ids = result.mutants.map { $0.id }
        for (index, id) in ids.enumerated() {
            #expect(id == "swift-mutation-testing_\(index)")
        }
    }

    @Test("Given CalcApp fixture, when run, then RunnerInput contract fields map from DiscoveryInput")
    func runnerInputContractFieldsMapCorrectly() async throws {
        let input = makeInput()
        let result = try await pipeline.run(input: input)

        #expect(result.projectPath == calcAppURL().path)
        #expect(result.scheme == "CalcApp")
        #expect(result.destination == "platform=macOS")
        #expect(result.timeout == 60)
        #expect(result.concurrency == 1)
        #expect(result.noCache == false)
    }
}

extension DiscoveryPipelineIntegrationTests {
    private func calcAppURL() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/CalcApp")
    }

    private func makeInput(
        excludePatterns: [String] = [],
        operators: [String] = []
    ) -> DiscoveryInput {
        let root = calcAppURL()
        return DiscoveryInput(
            projectPath: root.path,
            scheme: "CalcApp",
            destination: "platform=macOS",
            timeout: 60,
            concurrency: 1,
            noCache: false,
            sourcesPath: root.appending(path: "Sources").path,
            excludePatterns: excludePatterns,
            operators: operators
        )
    }
}
