import Foundation

struct XCTestRunPlist: Sendable, Equatable {
    typealias PlistSerializer = ([String: Any]) throws -> Data

    init?(_ data: Data) {
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is [String: Any]
        else { return nil }
        self.data = data
    }

    private let data: Data

    func activating(
        _ mutantID: String,
        activationFile: String? = nil,
        serialize: PlistSerializer = {
            try PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0)
        }
    ) -> Data {
        guard
            var dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
                as? [String: Any]
        else { return data }

        let activation = TestBundleInvocation.environment(mutantID: mutantID, activationFile: activationFile)

        if var configurations = dict["TestConfigurations"] as? [[String: Any]] {
            for index in configurations.indices {
                if var targets = configurations[index]["TestTargets"] as? [[String: Any]] {
                    for targetIndex in targets.indices {
                        var envVars = targets[targetIndex]["EnvironmentVariables"] as? [String: String] ?? [:]
                        envVars.merge(activation, uniquingKeysWith: Uniquing.last)
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
                    envVars.merge(activation, uniquingKeysWith: Uniquing.last)
                    targetDict["EnvironmentVariables"] = envVars
                    dict[key] = targetDict
                }
            }
        }

        return (try? serialize(dict)) ?? data
    }
}
