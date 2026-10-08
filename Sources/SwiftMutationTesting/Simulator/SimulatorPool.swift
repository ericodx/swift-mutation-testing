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

    nonisolated var usesSimulators: Bool { baseUDID != nil }

    private let baseUDID: String?
    private let destination: String
    private let launcher: any ProcessLaunching
    private let sessionID: String
    private var clonedUDIDs: [String] = []
    private var available: [SimulatorSlot] = []
    private var pending: [(id: UUID, continuation: CheckedContinuation<SimulatorSlot, Error>)] = []

    func setUp() async throws {
        guard let baseUDID else {
            available = (0 ..< size).map { _ in SimulatorSlot(udid: "", destination: destination) }
            return
        }

        await removeOrphanedClones()

        do {
            try await cloneBase(baseUDID)
            try await bootClones(clonedUDIDs)
        } catch {
            await tearDown()
            throw error
        }

        let clones = clonedUDIDs
        let platform =
            destination.components(separatedBy: ",")
            .first(where: { $0.hasPrefix("platform=") }) ?? "platform=iOS Simulator"
        available = clones.map { SimulatorSlot(udid: $0, destination: "\(platform),id=\($0)") }
    }

    private func cloneBase(_ base: String) async throws {
        let launcher = self.launcher
        let size = self.size
        let session = self.sessionID

        _ = try? await launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "shutdown", base],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            timeout: 30
        )

        try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0 ..< size {
                group.addTask {
                    let result = try await launcher.launchCapturing(
                        ProcessRequest(
                            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                            arguments: ["simctl", "clone", base, CloneName.make(session: session, index: index)],
                            environment: nil,
                            additionalEnvironment: [:],
                            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                            timeout: 60
                        )
                    )

                    guard result.exitCode == 0 else {
                        throw SimulatorError.cloneFailed(udid: base)
                    }

                    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            var firstError: (any Error)?
            while let outcome = await group.nextResult() {
                switch outcome {
                case .success(let udid): clonedUDIDs.append(udid)
                case .failure(let error): firstError = firstError ?? error
                }
            }
            if let firstError { throw firstError }
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
            try await group.waitForAll()
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

        await remove(clonedUDIDs)
    }

    static func orphanedClones(in listOutput: String, isAlive: (pid_t) -> Bool) -> [String] {
        guard
            let data = listOutput.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        return devices.values.flatMap { $0 }.compactMap { device in
            guard
                let name = device["name"] as? String,
                let udid = device["udid"] as? String,
                CloneName.isOrphaned(name, isAlive: isAlive)
            else { return nil }
            return udid
        }.sorted()
    }

    private func removeOrphanedClones() async {
        guard
            let listed = try? await launcher.launchCapturing(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                    arguments: ["simctl", "list", "devices", "--json"],
                    environment: nil,
                    additionalEnvironment: [:],
                    workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                    timeout: 30
                )
            ),
            listed.exitCode == 0
        else { return }

        await remove(Self.orphanedClones(in: listed.output, isAlive: ProcessTree.isAlive))
    }

    private func remove(_ udids: [String]) async {
        let launcher = self.launcher

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

    func cancelPending(id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let entry = pending.remove(at: index)
        entry.continuation.resume(throwing: CancellationError())
    }
}
