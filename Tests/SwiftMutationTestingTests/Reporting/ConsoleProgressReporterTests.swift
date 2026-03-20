import Foundation
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
}

private func captureOutput(_ block: () async -> Void) async -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    await block()

    fflush(stdout)
    dup2(originalStdout, STDOUT_FILENO)
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
