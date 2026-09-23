import Testing

@testable import SwiftMutationTesting

@Suite("BuildError")
struct BuildErrorTests {
    @Test("Given compilationFailed with output, when errorDescription accessed, then includes output and message")
    func compilationFailedWithOutput() {
        let error = BuildError.compilationFailed(output: "error: missing semicolon")
        #expect(error.errorDescription?.contains("missing semicolon") == true)
        #expect(error.errorDescription?.contains("Build failed") == true)
    }

    @Test("Given compilationFailed with empty output, when errorDescription accessed, then returns build failed message")
    func compilationFailedEmptyOutput() {
        let error = BuildError.compilationFailed(output: "")
        #expect(error.errorDescription == "Build failed. The schematized source could not be compiled.")
    }

    @Test("Given timedOut with output, when errorDescription accessed, then names the limit and the flag to raise")
    func timedOutWithOutput() {
        let error = BuildError.timedOut(seconds: 120, output: "compiling Foo.swift")
        #expect(error.errorDescription?.contains("compiling Foo.swift") == true)
        #expect(error.errorDescription?.contains("did not finish within 120s") == true)
        #expect(error.errorDescription?.contains("--build-timeout") == true)
    }

    @Test("Given timedOut and compilationFailed, when compared, then they are not equal")
    func timedOutIsNotCompilationFailed() {
        #expect(BuildError.timedOut(seconds: 1, output: "") != BuildError.compilationFailed(output: ""))
    }

    @Test("Given xctestrunNotFound, when errorDescription accessed, then returns expected message")
    func xctestrunNotFound() {
        let error = BuildError.xctestrunNotFound
        #expect(error.errorDescription == "xctestrun file not found after build.")
    }

    @Test("Given two compilationFailed errors, when compared, then they are equal")
    func compilationFailedEquality() {
        let lhs = BuildError.compilationFailed(output: "a")
        let rhs = BuildError.compilationFailed(output: "b")
        #expect(lhs == rhs)
    }

    @Test("Given compilationFailed and xctestrunNotFound, when compared, then they are not equal")
    func differentCasesNotEqual() {
        let lhs = BuildError.compilationFailed(output: "a")
        let rhs = BuildError.xctestrunNotFound
        #expect(lhs != rhs)
    }
}
