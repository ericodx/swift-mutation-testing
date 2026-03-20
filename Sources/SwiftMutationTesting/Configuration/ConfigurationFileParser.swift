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
        var inMutatorsBlock = false
        var currentMutatorName: String?
        var disabledMutators: [String] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            if indent == 0 {
                inMutatorsBlock = false
                currentMutatorName = nil
                parseTopLevel(trimmed, result: &result, lastKey: &lastKey, inMutatorsBlock: &inMutatorsBlock)
                continue
            }

            if inMutatorsBlock {
                parseMutatorLine(trimmed, currentName: &currentMutatorName, disabled: &disabledMutators)
                continue
            }

            if trimmed.hasPrefix("- "), let key = lastKey {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                listValues[key, default: []].append(item)
            }
        }

        for (key, items) in listValues {
            result[key] = items.joined(separator: ",")
        }

        if !disabledMutators.isEmpty {
            result["disabledMutators"] = disabledMutators.joined(separator: ",")
        }

        return result
    }

    private func parseTopLevel(
        _ trimmed: String,
        result: inout [String: String],
        lastKey: inout String?,
        inMutatorsBlock: inout Bool
    ) {
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return }
        let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !key.isEmpty else { return }
        lastKey = key
        if key == "mutators" {
            inMutatorsBlock = true
        } else if !value.isEmpty {
            result[key] = value
        }
    }

    private func parseMutatorLine(
        _ trimmed: String,
        currentName: inout String?,
        disabled: inout [String]
    ) {
        if trimmed.hasPrefix("- name:") {
            currentName = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("active: false"), let name = currentName {
            disabled.append(name)
        }
    }
}
