import Foundation

struct ConfigurationFileParser: Sendable {
    func parse(at projectPath: String) throws -> [String: String] {
        let fileURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".swift-mutation-testing.yml")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var result: [String: String] = [:]
        var lastKey: String?
        var listValues: [String: [String]] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            if trimmed.hasPrefix("- ") {
                guard let key = lastKey else { continue }
                let item = String(trimmed.dropFirst(2))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                listValues[key, default: []].append(item)
                continue
            }

            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                continue
            }

            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            guard !key.isEmpty else { continue }

            lastKey = key

            if !value.isEmpty {
                result[key] = value
            }
        }

        for (key, items) in listValues {
            result[key] = items.joined(separator: ",")
        }

        return result
    }
}
