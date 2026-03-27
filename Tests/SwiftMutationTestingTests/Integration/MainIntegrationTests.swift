import Foundation
import Testing

@Suite(.tags(.integration))
struct MainIntegrationTests {

    @Test("Given --help flag, when main is invoked, then exits with code 0")
    func mainExitsSuccessfullyWithHelpFlag() throws {
        let process = Process()
        process.executableURL = try binaryURL()
        process.arguments = ["--help"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("Given unknown flag, when main is invoked, then exits with non-zero code")
    func mainExitsWithErrorForUnknownFlag() throws {
        let process = Process()
        process.executableURL = try binaryURL()
        process.arguments = ["--unknown-flag-xyz"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
    }
}

private func binaryURL() throws -> URL {
    let binary = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: ".build/debug/swift-mutation-testing")

    try #require(
        FileManager.default.isExecutableFile(atPath: binary.path),
        "Binary not found at \(binary.path) — run swift build first"
    )

    return binary
}
