import Foundation

enum KillerTestFilter {

    static func filter(for killer: String) -> String? {
        if matches(killer, functionPattern) {
            return NSRegularExpression.escapedPattern(for: killer)
        }

        if matches(killer, xctestPattern), let lastDot = killer.lastIndex(of: ".") {
            return killer[..<lastDot] + "/" + killer[killer.index(after: lastDot)...]
        }

        return nil
    }

    // MARK: - Private

    private static let identifier = "[A-Za-z_][A-Za-z0-9_]*"
    private static let functionPattern = "^\(identifier)\\((?:\(identifier):)*\\)$"
    private static let xctestPattern = "^\(identifier)(?:\\.\(identifier))+$"

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
