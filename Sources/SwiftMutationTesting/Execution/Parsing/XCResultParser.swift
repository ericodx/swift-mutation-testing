import Foundation

struct XCResultParser: Sendable {
    enum Result: Sendable {
        case killed(by: String)
        case crashed
    }

    func parse(_ json: String) -> Result {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let nodes = root["testNodes"] as? [[String: Any]],
            let identifier = firstFailedTestCase(in: nodes)
        else { return .crashed }

        return .killed(by: identifier)
    }

    private func firstFailedTestCase(in nodes: [[String: Any]]) -> String? {
        for node in nodes {
            if node["nodeType"] as? String == "Test Case",
                node["result"] as? String == "Failed",
                let identifier = node["nodeIdentifier"] as? String
            {
                return identifier
            }

            if let children = node["children"] as? [[String: Any]],
                let found = firstFailedTestCase(in: children)
            {
                return found
            }
        }

        return nil
    }
}
