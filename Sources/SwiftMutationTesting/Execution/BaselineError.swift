import Foundation

enum BaselineError: Error, Equatable, LocalizedError {
    case testsFailed(tests: [String])

    case didNotFinish(seconds: Double)

    case runFailed(output: String)

    case buildFailed(output: String)

    var errorDescription: String? {
        switch self {
        case .testsFailed(let tests):
            return
                "The test suite fails before any mutation is applied, so every mutant would be "
                + "reported killed by a failure that is already there. Fix these first:\n"
                + tests.map { "  - \($0)" }.joined(separator: "\n")
                + "\n\nTests run against a sandbox copy of the project under the system temporary "
                + "directory, so a test that derives paths from #filePath can fail here while "
                + "passing in place. Pass --keep-logs <dir> to keep the suite's output as baseline.log."

        case .didNotFinish(let seconds):
            return
                "The unmutated test suite did not finish within \(formatted(seconds))s. Every mutant "
                + "runs the same suite under the same limit, so all of them would time out too. "
                + "Raise --timeout past the time the suite needs."

        case .runFailed(let output):
            let explanation =
                "The unmutated test suite could not be run, so no mutant's verdict would mean anything."
            return output.isEmpty ? explanation : output + "\n" + explanation

        case .buildFailed(let output):
            let explanation =
                "The unmutated project does not build, so every mutant would be reported unviable. "
                + "Make it build with xcodebuild or swift build from the command line first. "
                + "Pass --keep-logs <dir> to keep the build output as baseline.log."
            return output.isEmpty ? explanation : output + "\n" + explanation
        }
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%g", seconds)
    }
}
