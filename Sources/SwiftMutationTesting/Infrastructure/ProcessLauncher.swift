import Foundation

struct ProcessLauncher: Sendable, ProcessLaunching {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timedOut = TimeoutFlag()

                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(timeout))
                    timedOut.mark()
                    terminateProcessGroup(pid: process.processIdentifier)
                }

                process.terminationHandler = { proc in
                    timeoutTask.cancel()
                    let exitCode: Int32 = timedOut.value ? -1 : proc.terminationStatus
                    continuation.resume(returning: exitCode)
                }

                do {
                    try process.run()
                    setpgid(process.processIdentifier, process.processIdentifier)
                } catch {
                    timeoutTask.cancel()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            terminateProcessGroup(pid: process.processIdentifier)
        }
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL

        if let environment {
            process.environment = environment
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        process.standardOutput = fileHandle
        process.standardError = fileHandle

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timedOut = TimeoutFlag()

                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(timeout))
                    timedOut.mark()
                    terminateProcessGroup(pid: process.processIdentifier)
                }

                process.terminationHandler = { terminated in
                    timeoutTask.cancel()
                    fileHandle.closeFile()
                    let output = (try? String(contentsOf: tempURL, encoding: .utf8)) ?? ""
                    try? FileManager.default.removeItem(at: tempURL)
                    let exitCode: Int32 = timedOut.value ? -1 : terminated.terminationStatus
                    continuation.resume(returning: (exitCode: exitCode, output: output))
                }

                do {
                    try process.run()
                    setpgid(process.processIdentifier, process.processIdentifier)
                } catch {
                    timeoutTask.cancel()
                    fileHandle.closeFile()
                    try? FileManager.default.removeItem(at: tempURL)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            terminateProcessGroup(pid: process.processIdentifier)
        }
    }

    private func terminateProcessGroup(pid: Int32) {
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        Task {
            try? await Task.sleep(for: .seconds(5))
            kill(-pid, SIGKILL)
        }
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func mark() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}
