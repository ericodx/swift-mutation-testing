import Testing

@testable import SwiftMutationTesting

@Suite("Version")
struct VersionTests {
    @Test("Given name, then equals swift-mutation-testing")
    func nameIsCorrect() {
        #expect(Version.name == "swift-mutation-testing")
    }

    @Test("Given number in development build, then equals 0.0.0-dev")
    func numberIsDevPlaceholder() {
        #expect(Version.number == "0.0.0-dev")
    }

    @Test("Given current, then starts with name and number")
    func currentStartsWithNameAndNumber() {
        #expect(Version.current.hasPrefix("swift-mutation-testing 0.0.0-dev ["))
    }

    @Test("Given current, then ends with closing bracket")
    func currentEndsWithBracket() {
        #expect(Version.current.hasSuffix("]"))
    }

    @Test("Given current on macOS, then contains macos platform")
    func currentContainsMacosPlatform() {
        #expect(Version.current.contains("macos"))
    }

    @Test("Given current, then contains known architecture")
    func currentContainsKnownArchitecture() {
        let containsArch = Version.current.contains("arm64") || Version.current.contains("x86_64")
        #expect(containsArch)
    }
}
