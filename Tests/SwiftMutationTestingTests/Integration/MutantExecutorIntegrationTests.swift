import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite(.tags(.integration))
struct MutantExecutorIntegrationTests {

    @Test("Given fixture project with partial coverage, when executed, then killed and survived mutants match expected")
    func fixtureResultsMatchExpected() async throws {
        let fixtureURL = fixtureProjectURL()
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

        #expect(killed.count == 3)
        #expect(survived.count == 3)
        #expect(killedIDs == Set(["m1", "m2", "m4"]))
    }

    @Test("Given fixture project, when executed, then original source files are not modified")
    func fixtureSourceFilesNotModified() async throws {
        let fixtureURL = fixtureProjectURL()
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

private func fixtureProjectURL() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/CalcApp")
}

private func makeConfiguration(fixtureURL: URL) -> RunnerConfiguration {
    RunnerConfiguration(
        projectPath: fixtureURL.path,
        build: .init(
            projectType: .xcode(scheme: "CalcApp", destination: "platform=macOS"),
            timeout: 60.0, concurrency: 1, noCache: true),
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
        schematizedFiles: makeSchematizedFiles(fixtureURL: fixtureURL),
        supportFileContent: activatingSupportFileContent,
        mutants: makeMutants(fixtureURL: fixtureURL)
    )
}

private func makeSchematizedFiles(fixtureURL: URL) -> [SchematizedFile] {
    let calculatorPath = fixtureURL.appending(path: "Sources/Calculator.swift").path
    let validatorPath = fixtureURL.appending(path: "Sources/Validator.swift").path

    return [
        SchematizedFile(
            originalPath: calculatorPath,
            schematizedContent: """
                struct Calculator {
                    func add(_ a: Int, _ b: Int) -> Int {
                        (__swiftMutationTestingID == "m1") ? a - b : a + b
                    }
                    func subtract(_ a: Int, _ b: Int) -> Int {
                        (__swiftMutationTestingID == "m2") ? a + b : a - b
                    }
                    func isPositive(_ n: Int) -> Bool {
                        (__swiftMutationTestingID == "m3") ? n >= 0 : n > 0
                    }
                }
                """
        ),
        SchematizedFile(
            originalPath: validatorPath,
            schematizedContent: """
                struct Validator {
                    func isInRange(_ value: Int) -> Bool {
                        ((__swiftMutationTestingID == "m4") ? value > 0 : value >= 0)
                            && ((__swiftMutationTestingID == "m5") ? value < 100 : value <= 100)
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
}

private func calculatorMutants(path: String) -> [MutantDescriptor] {
    [
        MutantDescriptor(
            id: "m1", filePath: path,
            line: 2, column: 44, utf8Offset: 64,
            originalText: "+", mutatedText: "-",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace + with -", isSchematizable: true, mutatedSourceContent: nil
        ),
        MutantDescriptor(
            id: "m2", filePath: path,
            line: 3, column: 47, utf8Offset: 119,
            originalText: "-", mutatedText: "+",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace - with +", isSchematizable: true, mutatedSourceContent: nil
        ),
        MutantDescriptor(
            id: "m3", filePath: path,
            line: 4, column: 40, utf8Offset: 167,
            originalText: ">", mutatedText: ">=",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace > with >=", isSchematizable: true, mutatedSourceContent: nil
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
            description: "Replace >= with >", isSchematizable: true, mutatedSourceContent: nil
        ),
        MutantDescriptor(
            id: "m5", filePath: path,
            line: 2, column: 62, utf8Offset: 81,
            originalText: "<=", mutatedText: "<",
            operatorIdentifier: "binaryOperator", replacementKind: .binaryOperator,
            description: "Replace <= with <", isSchematizable: true, mutatedSourceContent: nil
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
                """
        )
    ]
}

private let activatingSupportFileContent =
    "import Foundation\n"
    + "var __swiftMutationTestingID: String"
    + #" { ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? "" }"#
