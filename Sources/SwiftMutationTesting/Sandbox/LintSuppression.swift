enum LintSuppression {
    static let opening = "// swiftlint:disable all\n"
    static let closing = "\n// swiftlint:enable all\n"

    static func wrapping(_ content: String) -> String {
        opening + content + closing
    }

    static func unwrapping(_ content: String) -> String {
        guard content.hasPrefix(opening), content.hasSuffix(closing) else { return content }
        return String(content.dropFirst(opening.count).dropLast(closing.count))
    }
}
