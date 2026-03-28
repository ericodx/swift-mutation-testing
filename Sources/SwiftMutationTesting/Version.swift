import Foundation

enum Version {

    static let name = "swift-mutation-testing"
    static let number = "0.0.0-dev"

    static var current: String {
        "\(name) \(number) [\(platform)]"
    }

    // MARK: - Private

    private static var platform: String {
        "\(architecture)-\(operatingSystem)"
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }

    private static var operatingSystem: String {
        #if os(macOS)
            "macos\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
        #elseif os(Linux)
            "linux"
        #else
            "unknown"
        #endif
    }
}
