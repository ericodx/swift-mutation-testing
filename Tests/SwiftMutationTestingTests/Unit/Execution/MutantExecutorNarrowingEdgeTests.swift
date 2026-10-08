import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor narrowing edges")
struct MutantExecutorNarrowingEdgeTests {

    @Test(
        "Given the compiler names a line past the end of the file, when narrowing runs, then the file is excluded whole"
    )
    func errorBeyondEndOfFileExcludesTheFile() async throws {
        let fixture = try Fixture(
            schema: """
                switch __swiftMutationTestingID {
                case "swift-mutation-testing_0":
                    let x = false
                default:
                    let x = true
                }
                """,
            errorLine: 99
        )
        defer { fixture.cleanUp() }

        let results = try await fixture.run()

        #expect(results.map(\.status) == [.survived])
    }

    @Test("Given the scan reaches the switch before a case, when narrowing runs, then no mutant outside it is blamed")
    func scanStopsAtTheSwitchItSitsIn() async throws {
        let fixture = try Fixture(
            schema: """
                case "swift-mutation-testing_0":
                let earlier = 1
                switch __swiftMutationTestingID {
                let broken = 2
                }
                """,
            errorLine: 4
        )
        defer { fixture.cleanUp() }

        let results = try await fixture.run()

        #expect(results.map(\.status) == [.survived])
    }

    @Test("Given a case above the error is not a mutant case, when narrowing runs, then it is not blamed")
    func aCaseThatIsNotAMutantCaseIsNotBlamed() async throws {
        let fixture = try Fixture(
            schema: """
                case "something-else":
                let broken = 2
                """,
            errorLine: 2
        )
        defer { fixture.cleanUp() }

        let results = try await fixture.run()

        #expect(results.map(\.status) == [.survived])
    }

    @Test("Given the error names a file the project does not have, when narrowing runs, then nothing is blamed for it")
    func errorNamingAFileOutsideTheProjectBlamesNothing() async throws {
        let directory = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(directory) }

        let sourceFile = directory.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm),
            launcher: SPMErrorAtLineMock(
                locations: [(fileName: "Ghost.swift", line: 1), (fileName: "Foo.swift", line: 1)]
            )
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [
                    makeMutantDescriptor(
                        id: "swift-mutation-testing_0", filePath: sourceFile.path,
                        isSchematizable: true, sourceContentHash: "hash"
                    )
                ]
            )
        )

        #expect(results.map(\.status) == [.survived])
    }

    @Test(
        "Given the error names a file no mutant touches, when narrowing runs, then the others keep their verdicts"
    )
    func errorNamingAFileWithoutMutantsKeepsTheOthers() async throws {
        let directory = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(directory) }

        let sourceFile = directory.appendingPathComponent("Foo.swift")
        let untouched = directory.appendingPathComponent("Bar.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "let y = true".write(to: untouched, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm),
            launcher: SPMErrorAtLineMock(fileName: "Bar.swift", line: 1)
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [
                    makeMutantDescriptor(
                        id: "swift-mutation-testing_0", filePath: sourceFile.path,
                        isSchematizable: true, sourceContentHash: "hash"
                    )
                ]
            )
        )

        #expect(results.map(\.status) == [.survived])
    }

    @Test("Given an error line that names no Swift file, when narrowing runs, then no path is read from it")
    func errorLineWithoutASwiftPathIsIgnored() async throws {
        let directory = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(directory) }

        let sourceFile = directory.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm),
            launcher: SPMErrorAtLineMock(fileName: "Package.resolved", line: 1)
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
                ],
                mutants: [
                    makeMutantDescriptor(
                        id: "swift-mutation-testing_0", filePath: sourceFile.path,
                        isSchematizable: true, sourceContentHash: "hash"
                    )
                ]
            )
        )

        #expect(results.map(\.status) == [.survived])
    }

    @Test("Given the schema cannot be regenerated, when narrowing runs, then the file is left to the fallback")
    func aSchemaThatCannotBeRegeneratedFallsBack() async throws {
        let fixture = try Fixture(
            schema: """
                switch __swiftMutationTestingID {
                case "swift-mutation-testing_0":
                    let x = false
                default:
                    let x = true
                }
                """,
            errorLine: 2,
            extraMutantID: "not-a-generated-id"
        )
        defer { fixture.cleanUp() }

        let results = try await fixture.run()

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .survived })
    }

    @Test(
        "Given the failing file cannot be read as text, when narrowing runs, then its mutants go to the fallback"
    )
    func aFileThatIsNotUTF8IsLeftToTheFallback() async throws {
        let directory = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(directory) }

        let sourceFile = directory.appendingPathComponent("Foo.swift")
        let notText = directory.appendingPathComponent("Bad.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: notText)

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm),
            launcher: SPMErrorAtLineMock(fileName: "Bad.swift", line: 1)
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false"),
                    SchematizedFile(originalPath: notText.path, schematizedContent: "let y = false"),
                ],
                mutants: [
                    makeMutantDescriptor(
                        id: "swift-mutation-testing_0", filePath: sourceFile.path,
                        isSchematizable: true, sourceContentHash: "hash"
                    ),
                    makeMutantDescriptor(
                        id: "swift-mutation-testing_1", filePath: notText.path,
                        utf8Offset: 1, isSchematizable: true, sourceContentHash: "hash"
                    ),
                ]
            )
        )

        let byMutant = Dictionary(uniqueKeysWithValues: results.map { ($0.descriptor.id, $0.status) })

        #expect(byMutant["swift-mutation-testing_1"] == .unviable)
        #expect(byMutant["swift-mutation-testing_0"] == .survived)
    }

    @Test("Given narrowing gives up after excluding a mutant, when the fallback runs, then each mutant has one verdict")
    func aMutantTheNarrowerExcludedIsNotTestedAgainByTheFallback() async throws {
        let directory = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(directory) }

        let kept = directory.appendingPathComponent("Foo.swift")
        let broken = directory.appendingPathComponent("Bar.swift")
        try "func f() { let x = true }".write(to: kept, atomically: true, encoding: .utf8)
        try "func g() { let y = true }".write(to: broken, atomically: true, encoding: .utf8)

        let mutants = [
            makeMutantDescriptor(
                id: "swift-mutation-testing_0", filePath: kept.path, utf8Offset: 19,
                originalText: "true", mutatedText: "false", replacementKind: .booleanLiteral,
                isSchematizable: true, sourceContentHash: "hash"
            ),
            makeMutantDescriptor(
                id: "swift-mutation-testing_1", filePath: broken.path, utf8Offset: 19,
                originalText: "true", mutatedText: "false", replacementKind: .booleanLiteral,
                isSchematizable: true, sourceContentHash: "hash"
            ),
        ]
        let keptSchema = try #require(SchemaNarrower.regeneratedSchema(originalPath: kept.path, keeping: [mutants[0]]))
        let brokenSchema = try #require(
            SchemaNarrower.regeneratedSchema(originalPath: broken.path, keeping: [mutants[1]])
        )
        let caseLine = try #require(
            brokenSchema.components(separatedBy: "\n").firstIndex { $0.contains("case \"swift-mutation-testing_1\":") }
        )

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm),
            launcher: SPMErrorAtLineMock(locations: [(fileName: "Bar.swift", line: caseLine + 2)], failingBuilds: 2)
        )

        let results = try await executor.execute(
            makeRunnerInput(
                projectPath: directory.path,
                projectType: .spm,
                schematizedFiles: [
                    SchematizedFile(originalPath: kept.path, schematizedContent: keptSchema),
                    SchematizedFile(originalPath: broken.path, schematizedContent: brokenSchema),
                ],
                mutants: mutants
            )
        )

        #expect(results.map(\.descriptor.id).sorted() == ["swift-mutation-testing_0", "swift-mutation-testing_1"])
    }

    private struct Fixture {
        let directory: URL
        let sourceFile: URL
        let schema: String
        let errorLine: Int
        let extraMutantID: String?

        init(schema: String, errorLine: Int, extraMutantID: String? = nil) throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            sourceFile = directory.appendingPathComponent("Foo.swift")
            self.schema = schema
            self.errorLine = errorLine
            self.extraMutantID = extraMutantID
            try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }

        private var mutants: [MutantDescriptor] {
            let ids = ["swift-mutation-testing_0"] + (extraMutantID.map { [$0] } ?? [])

            return ids.map { id in
                makeMutantDescriptor(
                    id: id, filePath: sourceFile.path,
                    originalText: "true", mutatedText: "false",
                    replacementKind: .booleanLiteral, isSchematizable: true,
                    mutatedSourceContent: "let x = false", sourceContentHash: "hash"
                )
            }
        }

        func run() async throws -> [ExecutionResult] {
            let executor = MutantExecutor(
                configuration: makeRunnerConfiguration(projectPath: directory.path, projectType: .spm),
                launcher: SPMErrorAtLineMock(line: errorLine)
            )

            return try await executor.execute(
                makeRunnerInput(
                    projectPath: directory.path,
                    projectType: .spm,
                    schematizedFiles: [
                        SchematizedFile(originalPath: sourceFile.path, schematizedContent: schema)
                    ],
                    mutants: mutants
                )
            )
        }
    }
}
