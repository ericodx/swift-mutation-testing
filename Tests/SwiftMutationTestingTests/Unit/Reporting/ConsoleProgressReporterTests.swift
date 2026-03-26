import Testing

@testable import SwiftMutationTesting

@Suite("ConsoleProgressReporter", .serialized)
struct ConsoleProgressReporterTests {
    private let reporter = ConsoleProgressReporter()

    @Test("Given discoveryFinished with all schematizable, when reported, then output has count and duration")
    func discoveryFinishedAllSchematizable() async {
        let output = await captureOutput {
            await reporter.report(
                .discoveryFinished(
                    mutantCount: 10,
                    schematizableCount: 10,
                    incompatibleCount: 0,
                    duration: 1.5
                ))
        }

        #expect(output.contains("10 mutants"))
        #expect(output.contains("10 schematizable"))
        #expect(output.contains("1.5s"))
        #expect(!output.contains("incompatible"))
    }

    @Test("Given discoveryFinished with incompatible mutants, when reported, then incompatible count is shown")
    func discoveryFinishedWithIncompatible() async {
        let output = await captureOutput {
            await reporter.report(
                .discoveryFinished(
                    mutantCount: 8,
                    schematizableCount: 5,
                    incompatibleCount: 3,
                    duration: 0.3
                ))
        }

        #expect(output.contains("8 mutants"))
        #expect(output.contains("5 schematizable"))
        #expect(output.contains("3 incompatible"))
    }

    @Test("Given discoveryFinished with zero mutants, when reported, then output shows zero")
    func discoveryFinishedZeroMutants() async {
        let output = await captureOutput {
            await reporter.report(
                .discoveryFinished(
                    mutantCount: 0,
                    schematizableCount: 0,
                    incompatibleCount: 0,
                    duration: 0.0
                ))
        }

        #expect(output.contains("0 mutants"))
        #expect(output.contains("0 schematizable"))
    }

    @Test("Given simulatorPoolReady, when reported, then Testing mutants header is printed")
    func simulatorPoolReadyPrintsTestingMutantsHeader() async {
        let output = await captureOutput {
            await reporter.report(.simulatorPoolReady(size: 4))
        }

        #expect(output.contains("Testing mutants..."))
        #expect(output.contains("4 simulators ready"))
    }

    @Test("Given mutantFinished, when reported, then line contains filename and line number inline")
    func mutantFinishedPrintsInlineFilenameAndLine() async {
        let descriptor = MutantDescriptor(
            id: "1", filePath: "/project/Sources/Foo.swift",
            line: 10, column: 5, utf8Offset: 0,
            originalText: "true", mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral, description: "",
            isSchematizable: true, mutatedSourceContent: nil
        )

        let output = await captureOutput {
            await reporter.report(.mutantFinished(descriptor: descriptor, status: .survived, index: 1, total: 4))
        }

        #expect(output.contains("1/4"))
        #expect(output.contains("BooleanLiteralReplacement"))
        #expect(output.contains("Foo.swift:10"))
    }

    @Test("Given two mutants in same file, when reported, then each line shows filename and line number")
    func mutantFinishedSameFileEachLineShowsFilename() async {
        let reporter2 = ConsoleProgressReporter()
        let descriptor = MutantDescriptor(
            id: "1", filePath: "/project/Sources/Bar.swift",
            line: 5, column: 1, utf8Offset: 0,
            originalText: "a", mutatedText: "b",
            operatorIdentifier: "NegateConditional",
            replacementKind: .binaryOperator, description: "",
            isSchematizable: true, mutatedSourceContent: nil
        )

        let output = await captureOutput {
            await reporter2.report(
                .mutantFinished(descriptor: descriptor, status: .killed(by: "t"), index: 1, total: 2))
            await reporter2.report(
                .mutantFinished(descriptor: descriptor, status: .survived, index: 2, total: 2))
        }

        #expect(output.components(separatedBy: "Bar.swift:5").count == 3)
    }

    @Test("Given mutants from two different files, when reported, then each line shows its own filename")
    func mutantFinishedDifferentFilesEachLineShowsOwnFilename() async {
        let reporter3 = ConsoleProgressReporter()
        let alpha = MutantDescriptor(
            id: "1", filePath: "/project/Sources/Alpha.swift",
            line: 1, column: 1, utf8Offset: 0,
            originalText: "", mutatedText: "",
            operatorIdentifier: "NegateConditional",
            replacementKind: .binaryOperator, description: "",
            isSchematizable: true, mutatedSourceContent: nil
        )
        let beta = MutantDescriptor(
            id: "2", filePath: "/project/Sources/Beta.swift",
            line: 2, column: 1, utf8Offset: 0,
            originalText: "", mutatedText: "",
            operatorIdentifier: "RemoveSideEffects",
            replacementKind: .removeStatement, description: "",
            isSchematizable: true, mutatedSourceContent: nil
        )

        let output = await captureOutput {
            await reporter3.report(.mutantFinished(descriptor: alpha, status: .killed(by: "t"), index: 1, total: 2))
            await reporter3.report(.mutantFinished(descriptor: beta, status: .survived, index: 2, total: 2))
        }

        #expect(output.contains("Alpha.swift:1"))
        #expect(output.contains("Beta.swift:2"))
    }

    @Test("Given loadedFromCache event, when reported, then output contains mutant count")
    func loadedFromCachePrintsMutantCount() async {
        let output = await captureOutput {
            await reporter.report(.loadedFromCache(mutantCount: 42))
        }

        #expect(output.contains("42"))
        #expect(output.contains("cache"))
    }

    @Test("Given buildStarted event, when reported, then output contains building message")
    func buildStartedPrintsBuildingMessage() async {
        let output = await captureOutput {
            await reporter.report(.buildStarted)
        }

        #expect(output.contains("Building for testing"))
    }

    @Test("Given buildFinished event, when reported, then output contains duration")
    func buildFinishedPrintsDuration() async {
        let output = await captureOutput {
            await reporter.report(.buildFinished(duration: 3.7))
        }

        #expect(output.contains("3.7s"))
    }

    @Test("Given mutantStarted event, when reported, then no output is produced")
    func mutantStartedProducesNoOutput() async {
        let descriptor = MutantDescriptor(
            id: "1", filePath: "/project/Sources/Foo.swift",
            line: 1, column: 1, utf8Offset: 0,
            originalText: "a", mutatedText: "b",
            operatorIdentifier: "NegateConditional",
            replacementKind: .binaryOperator, description: "",
            isSchematizable: true, mutatedSourceContent: nil
        )

        let output = await captureOutput {
            await reporter.report(.mutantStarted(descriptor: descriptor, index: 1, total: 2))
        }

        #expect(output.isEmpty)
    }

    @Test("Given fallbackBuildStarted event, when reported, then no output is produced")
    func fallbackBuildStartedProducesNoOutput() async {
        let output = await captureOutput {
            await reporter.report(.fallbackBuildStarted(filePath: "/project/Sources/Foo.swift"))
        }

        #expect(output.isEmpty)
    }

    @Test("Given fallbackBuildFinished event, when reported, then no output is produced")
    func fallbackBuildFinishedProducesNoOutput() async {
        let output = await captureOutput {
            await reporter.report(.fallbackBuildFinished(filePath: "/project/Sources/Foo.swift", success: true))
        }

        #expect(output.isEmpty)
    }
}
