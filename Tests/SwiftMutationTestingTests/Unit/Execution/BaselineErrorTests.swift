import Testing

@testable import SwiftMutationTesting

@Suite("BaselineError")
struct BaselineErrorTests {

    @Test("Given testsFailed, when errorDescription accessed, then lists every named test")
    func testsFailedListsTests() {
        let error = BaselineError.testsFailed(tests: ["FooTests.testBar", "FooTests.testBaz"])

        #expect(error.errorDescription?.contains("  - FooTests.testBar") == true)
        #expect(error.errorDescription?.contains("  - FooTests.testBaz") == true)
    }

    @Test("Given testsFailed, when errorDescription accessed, then points at the sandbox as a cause")
    func testsFailedMentionsSandbox() {
        let error = BaselineError.testsFailed(tests: ["FooTests.testBar"])

        #expect(error.errorDescription?.contains("#filePath") == true)
    }

    @Test("Given didNotFinish, when errorDescription accessed, then names the limit and suggests --timeout")
    func didNotFinishNamesTimeout() {
        let error = BaselineError.didNotFinish(seconds: 30)

        #expect(error.errorDescription?.contains("30s") == true)
        #expect(error.errorDescription?.contains("--timeout") == true)
    }

    @Test("Given runFailed with output, when errorDescription accessed, then includes the output")
    func runFailedIncludesOutput() {
        let error = BaselineError.runFailed(output: "dyld: library not loaded")

        #expect(error.errorDescription?.contains("dyld: library not loaded") == true)
        #expect(error.errorDescription?.contains("could not be run") == true)
    }

    @Test("Given runFailed with empty output, when errorDescription accessed, then returns the explanation alone")
    func runFailedWithEmptyOutput() {
        let error = BaselineError.runFailed(output: "")

        #expect(
            error.errorDescription
                == "The unmutated test suite could not be run, so no mutant's verdict would mean anything."
        )
    }

    @Test("Given two testsFailed with different tests, when compared, then they are not equal")
    func testsFailedEqualityComparesTests() {
        #expect(BaselineError.testsFailed(tests: ["a"]) != BaselineError.testsFailed(tests: ["b"]))
        #expect(BaselineError.testsFailed(tests: ["a"]) == BaselineError.testsFailed(tests: ["a"]))
    }
}
