import Foundation

struct SimulatorManager: Sendable {
    let launcher: any ProcessLaunching

    static func requiresSimulatorPool(for destination: String) -> Bool {
        guard !destination.contains("platform=macOS") else { return false }
        return destination.contains("Simulator") || !destination.contains("platform=")
    }

    func resolveBaseUDID(for destination: String) async throws -> String {
        let udid: String

        if let value = parseValue(for: "id", in: destination) {
            udid = value
        } else if let name = parseValue(for: "name", in: destination) {
            udid = try await findUDID(named: name, destination: destination)
        } else {
            throw SimulatorError.deviceNotFound(destination: destination)
        }

        return udid
    }

    func waitForBooted(udid: String) async throws {
        for _ in 0 ..< 60 {
            let result = try await launcher.launchCapturing(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "devices", "--json"],
                environment: nil,
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                timeout: 10
            )

            if isBooted(udid: udid, in: result.output) { return }

            try await Task.sleep(for: .milliseconds(500))
        }

        throw SimulatorError.bootTimeout(udid: udid)
    }

    private func parseValue(for key: String, in destination: String) -> String? {
        let prefix = "\(key)="
        return destination.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func findUDID(named name: String, destination: String) async throws -> String {
        let result = try await launcher.launchCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list", "devices", "--json"],
            environment: nil,
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 10
        )

        guard
            let data = result.output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = json["devices"] as? [String: [[String: Any]]]
        else { throw SimulatorError.deviceNotFound(destination: destination) }

        for list in devices.values {
            for device in list {
                if device["name"] as? String == name, let udid = device["udid"] as? String {
                    return udid
                }
            }
        }

        throw SimulatorError.deviceNotFound(destination: destination)
    }

    private func isBooted(udid: String, in output: String) -> Bool {
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = json["devices"] as? [String: [[String: Any]]]
        else { return false }

        for list in devices.values {
            for device in list
            where device["udid"] as? String == udid && device["state"] as? String == "Booted" {
                return true
            }
        }

        return false
    }
}
