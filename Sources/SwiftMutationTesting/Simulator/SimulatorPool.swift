import Foundation

actor SimulatorPool {
    init(baseUDID: String?, size: Int, destination: String, launcher: any ProcessLaunching) {
        self.baseUDID = baseUDID
        self.size = size
        self.destination = destination
        self.launcher = launcher
        self.sessionID = String(UUID().uuidString.prefix(8)).lowercased()
    }

    nonisolated let size: Int

    private let baseUDID: String?
    private let destination: String
    private let launcher: any ProcessLaunching
    private let sessionID: String
    private var clonedUDIDs: [String] = []
    private var available: [SimulatorSlot] = []
    private var pending: [(id: UUID, continuation: CheckedContinuation<SimulatorSlot, Error>)] = []

    func setUp() async throws {
        guard let baseUDID else {
            available = [SimulatorSlot(udid: "", destination: destination)]
            return
        }

        let clones = try await cloneBase(baseUDID)
        clonedUDIDs = clones
        try await bootClones(clones)

        let platform =
            destination.components(separatedBy: ",")
            .first(where: { $0.hasPrefix("platform=") }) ?? "platform=iOS Simulator"
        available = clones.map { SimulatorSlot(udid: $0, destination: "\(platform),id=\($0)") }
    }

    private func cloneBase(_ base: String) async throws -> [String] {
        let launcher = self.launcher
        let size = self.size
        let session = self.sessionID

        _ = try? await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "shutdown", base],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 30
        )

        return try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0 ..< size {
                group.addTask {
                    let result = try await launcher.launchCapturing(
                        executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                        arguments: ["simctl", "clone", base, "XMR-\(session)-\(index)"],
                        environment: nil,
                        workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                        timeout: 60
                    )

                    guard result.exitCode == 0 else {
                        throw SimulatorError.cloneFailed(udid: base)
                    }

                    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            var results: [String] = []
            for try await udid in group { results.append(udid) }
            return results
        }
    }

    private func bootClones(_ clones: [String]) async throws {
        let launcher = self.launcher

        try await withThrowingTaskGroup(of: Void.self) { group in
            for udid in clones {
                group.addTask {
                    _ = try await launcher.launch(
                        executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                        arguments: ["simctl", "boot", udid],
                        workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                        timeout: 60
                    )
                    try await SimulatorManager(launcher: launcher).waitForBooted(udid: udid)
                }
            }
            for try await _ in group {}
        }
    }

    func acquire() async throws -> SimulatorSlot {
        if !available.isEmpty {
            return available.removeFirst()
        }

        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelPending(id: id) }
        }
    }

    func release(_ slot: SimulatorSlot) async {
        if let entry = pending.first {
            pending.removeFirst()
            entry.continuation.resume(returning: slot)
        } else {
            available.append(slot)
        }
    }

    func tearDown() async {
        guard baseUDID != nil else { return }

        let launcher = self.launcher
        let udids = clonedUDIDs

        await withTaskGroup(of: Void.self) { group in
            for udid in udids {
                group.addTask {
                    _ = try? await launcher.launch(
                        executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                        arguments: ["simctl", "shutdown", udid],
                        workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                        timeout: 30
                    )
                    _ = try? await launcher.launch(
                        executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                        arguments: ["simctl", "delete", udid],
                        workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                        timeout: 30
                    )
                }
            }
        }
    }

    private func cancelPending(id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let entry = pending.remove(at: index)
        entry.continuation.resume(throwing: CancellationError())
    }
}
