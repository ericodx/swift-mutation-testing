enum UTF8Splice {
    static func substring(of content: String, from start: Int, to end: Int) -> String? {
        let bytes = Array(content.utf8)
        guard start >= 0, start <= end, end <= bytes.count else { return nil }
        return String(bytes: bytes[start ..< end], encoding: .utf8)
    }

    static func replacing(from start: Int, to end: Int, in content: String, with replacement: String) -> String? {
        var bytes = Array(content.utf8)
        guard start >= 0, start <= end, end <= bytes.count else { return nil }
        bytes.replaceSubrange(start ..< end, with: replacement.utf8)
        return String(bytes: bytes, encoding: .utf8)
    }

    static func isRange(from start: Int, to end: Int, in bytes: [UInt8]) -> Bool {
        start >= 0 && start <= end && end <= bytes.count
    }

    static func replacing(from start: Int, to end: Int, in bytes: [UInt8], with replacement: String) -> String? {
        guard isRange(from: start, to: end, in: bytes) else { return nil }
        var spliced = bytes
        spliced.replaceSubrange(start ..< end, with: replacement.utf8)
        return String(bytes: spliced, encoding: .utf8)
    }

    static func inserting(_ text: String, at offset: Int, in content: String) -> String? {
        replacing(from: offset, to: offset, in: content, with: text)
    }
}
