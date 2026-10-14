import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite(.tags(.integration), .serialized, .notInsideAMutationRun)
struct MutantExecutorIntegrationTests {

    @Test("Given fixture project with partial coverage, when executed, then each verdict and its activation match")
    func fixtureResultsMatchExpected() async throws {
        let fixture = try FixtureCopy.make("CalcApp")
        defer { fixture.remove() }
        let fixtureURL = fixture.url
        let configuration = makeConfiguration(fixtureURL: fixtureURL)
        let input = makeInput(fixtureURL: fixtureURL)

        let results = try await MutantExecutor(
            configuration: configuration,
            launcher: XcodeProcessLauncher()
        ).execute(input)

        let killed = results.filter {
            if case .killed = $0.status { return true }
            return false
        }
        let survived = results.filter { $0.status == .survived }
        let killedIDs = Set(killed.map { $0.descriptor.id })

        let activation = Dictionary(uniqueKeysWithValues: results.map { ($0.descriptor.id, $0.activated) })

        #expect(killed.count == 4)
        #expect(survived.count == 2)
        #expect(killedIDs == Set(["m1", "m2", "m4", "mi2"]))
        #expect(results.first { $0.descriptor.id == "mi1" }?.status == .noCoverage)
        #expect(activation["mi1"] == .some(false))
        #expect(activation["mi2"] == .some(true))
    }

    @Test("Given fixture project, when executed, then original source files are not modified")
    func fixtureSourceFilesNotModified() async throws {
        let fixture = try FixtureCopy.make("CalcApp")
        defer { fixture.remove() }
        let fixtureURL = fixture.url
        let calculatorURL = fixtureURL.appending(path: "Sources/Calculator.swift")

        let before = try String(contentsOf: calculatorURL, encoding: .utf8)

        let configuration = makeConfiguration(fixtureURL: fixtureURL)
        let input = makeInput(fixtureURL: fixtureURL)
        _ = try await MutantExecutor(
            configuration: configuration,
            launcher: XcodeProcessLauncher()
        ).execute(input)

        let after = try String(contentsOf: calculatorURL, encoding: .utf8)

        #expect(before == after)
    }
}

private func makeConfiguration(fixtureURL: URL) -> RunnerConfiguration {
    RunnerConfiguration(
        projectPath: fixtureURL.path,
        build: .init(
            projectType: .xcode(scheme: "CalcApp", destination: "platform=macOS"),
            xcodebuildArguments: [], timeout: 60.0, buildTimeout: 60.0, concurrency: 1, noCache: true),
        reporting: .init(quiet: true),
        filter: .init(excludePatterns: [], operators: [])
    )
}

private func makeInput(fixtureURL: URL) -> RunnerInput {
    RunnerInput(
        projectPath: fixtureURL.path,
        projectType: .xcode(scheme: "CalcApp", destination: "platform=macOS"),
        timeout: 120.0,
        concurrency: 1,
        noCache: true,
        schematizedFiles: applied(
            makeSchematizedFiles(fixtureURL: fixtureURL), for: makeMutants(fixtureURL: fixtureURL)
        ),
        mutants: makeMutants(fixtureURL: fixtureURL)
    )
}

private func makeSchematizedFiles(fixtureURL: URL) -> [SchematizedFile] {
    let calculatorPath = fixtureURL.appending(path: "Sources/Calculator.swift").path
    let validatorPath = fixtureURL.appending(path: "Sources/Validator.swift").path

    let (calculatorID, calculatorActivation) = (
        SupportDeclarations.identifier(for: calculatorPath), SupportDeclarations.activationCall(for: calculatorPath)
    )
    let (validatorID, validatorActivation) = (
        SupportDeclarations.identifier(for: validatorPath), SupportDeclarations.activationCall(for: validatorPath)
    )

    return [
        SchematizedFile(
            originalPath: calculatorPath,
            schematizedContent: """
                struct Calculator {
                    func add(_ a: Int, _ b: Int) -> Int {
                        (\(calculatorID) == "m1") ? (\(calculatorActivation), a - b).1 : a + b
                    }
                    func subtract(_ a: Int, _ b: Int) -> Int {
                        (\(calculatorID) == "m2") ? (\(calculatorActivation), a + b).1 : a - b
                    }
                    func isPositive(_ n: Int) -> Bool {
                        (\(calculatorID) == "m3") ? (\(calculatorActivation), n >= 0).1 : n > 0
                    }
                }
                """
        ),
        SchematizedFile(
            originalPath: validatorPath,
            schematizedContent: """
                struct Validator {
                    func isInRange(_ value: Int) -> Bool {
                        ((\(validatorID) == "m4")
                            ? (\(validatorActivation), value > 0).1 : value >= 0)
                            && ((\(validatorID) == "m5")
                                ? (\(validatorActivation), value < 100).1 : value <= 100)
                    }
                }
                """
        ),
    ]
}

private func makeMutants(fixtureURL: URL) -> [MutantDescriptor] {
    let calculatorPath = fixtureURL.appending(path: "Sources/Calculator.swift").path
    let validatorPath = fixtureURL.appending(path: "Sources/Validator.swift").path
    let logicPath = fixtureURL.appending(path: "Sources/Logic.swift").path

    return calculatorMutants(path: calculatorPath)
        + validatorMutants(path: validatorPath)
        + incompatibleMutants(path: logicPath)
        + [incompatibleCalculatorMutant(path: calculatorPath)]
}

private func calculatorMutants(path: String) -> [MutantDescriptor] {
    [
        MutantDescriptor(
            id: "m1", filePath: path,
            line: 2, column: 44, utf8Offset: 64,
            originalText: "+", mutatedText: "-",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace + with -", isSchematizable: true, mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        ),
        MutantDescriptor(
            id: "m2", filePath: path,
            line: 3, column: 47, utf8Offset: 119,
            originalText: "-", mutatedText: "+",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace - with +", isSchematizable: true, mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        ),
        MutantDescriptor(
            id: "m3", filePath: path,
            line: 4, column: 40, utf8Offset: 167,
            originalText: ">", mutatedText: ">=",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace > with >=", isSchematizable: true, mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        ),
    ]
}

private func validatorMutants(path: String) -> [MutantDescriptor] {
    [
        MutantDescriptor(
            id: "m4", filePath: path,
            line: 2, column: 49, utf8Offset: 68,
            originalText: ">=", mutatedText: ">",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace >= with >", isSchematizable: true, mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        ),
        MutantDescriptor(
            id: "m5", filePath: path,
            line: 2, column: 62, utf8Offset: 81,
            originalText: "<=", mutatedText: "<",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace <= with <", isSchematizable: true, mutatedSourceContent: nil,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        ),
    ]
}

private func incompatibleMutants(path: String) -> [MutantDescriptor] {
    [
        MutantDescriptor(
            id: "mi1", filePath: path,
            line: 2, column: 45, utf8Offset: 59,
            originalText: ">=", mutatedText: ">",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace >= with >",
            isSchematizable: false,
            mutatedSourceContent: """
                struct Logic {
                    func isNonNegative(_ n: Int) -> Bool { n > 0 }
                }
                """,
            sourceContentHash: "test-hash",
            fingerprint: "fingerprint"
        )
    ]
}

private func incompatibleCalculatorMutant(path: String) -> MutantDescriptor {
    let original = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    return MutantDescriptor(
        id: "mi2", filePath: path,
        line: 2, column: 44, utf8Offset: 64,
        originalText: "+", mutatedText: "-",
        operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
        description: "Replace + with -",
        isSchematizable: false,
        mutatedSourceContent: original.replacingOccurrences(of: "a + b", with: "a - b"),
        sourceContentHash: "test-hash",
        fingerprint: "fingerprint"
    )
}
