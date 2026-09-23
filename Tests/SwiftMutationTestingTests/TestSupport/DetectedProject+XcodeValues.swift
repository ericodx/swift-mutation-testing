@testable import SwiftMutationTesting

extension DetectedProject {
    var scheme: String? {
        guard case .xcode(let xScheme, _, _) = kind else { return nil }
        return xScheme
    }

    var allSchemes: [String] {
        guard case .xcode(_, let all, _) = kind else { return [] }
        return all
    }

    var destination: String {
        guard case .xcode(_, _, let dest) = kind else { return "platform=macOS" }
        return dest
    }
}
