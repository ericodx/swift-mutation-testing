import Foundation

struct XCResultParser: Sendable {
    enum Result: Sendable {
        case killed(by: String)
        case crashed
    }

    func parse(_ json: String) -> Result {
        let data = Data(json.utf8)

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let issues = root["issues"] as? [String: Any],
            let summaries = issues["testFailureSummaries"] as? [String: Any],
            let values = summaries["_values"] as? [[String: Any]],
            let first = values.first,
            let nameDict = first["testCaseName"] as? [String: Any],
            let name = nameDict["_value"] as? String
        else { return .crashed }

        return .killed(by: name)
    }
}
