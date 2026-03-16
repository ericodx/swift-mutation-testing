import Foundation

struct XCTestRunPlist: Sendable, Equatable {
    init?(_ data: Data) {
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is [String: Any]
        else { return nil }
        self.data = data
    }

    private let data: Data

    func activating(_ mutantID: String) -> Data? {
        guard
            var dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
                as? [String: Any]
        else { return nil }

        if var configurations = dict["TestConfigurations"] as? [[String: Any]] {
            for index in configurations.indices {
                if var targets = configurations[index]["TestTargets"] as? [[String: Any]] {
                    for targetIndex in targets.indices {
                        var envVars = targets[targetIndex]["EnvironmentVariables"] as? [String: String] ?? [:]
                        envVars["__SWIFT_MUTATION_TESTING_ACTIVE"] = mutantID
                        targets[targetIndex]["EnvironmentVariables"] = envVars
                    }
                    configurations[index]["TestTargets"] = targets
                }
            }
            dict["TestConfigurations"] = configurations
        } else {
            for key in dict.keys where !key.hasPrefix("__") {
                if var targetDict = dict[key] as? [String: Any] {
                    var envVars = targetDict["EnvironmentVariables"] as? [String: String] ?? [:]
                    envVars["__SWIFT_MUTATION_TESTING_ACTIVE"] = mutantID
                    targetDict["EnvironmentVariables"] = envVars
                    dict[key] = targetDict
                }
            }
        }

        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}
