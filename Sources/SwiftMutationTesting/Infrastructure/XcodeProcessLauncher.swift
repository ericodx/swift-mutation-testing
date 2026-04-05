import Foundation

struct XcodeProcessLauncher: Sendable, ProcessLaunching {
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

        let killedByUs = KilledByUsFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startProcess(process, killedByUs: killedByUs, timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier)
        }
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        additionalEnvironment: [String: String],
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

        if !additionalEnvironment.isEmpty {
            var env = process.environment ?? ProcessInfo.processInfo.environment
            for (key, value) in additionalEnvironment {
                env[key] = value
            }
            process.environment = env
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        process.standardOutput = fileHandle
        process.standardError = fileHandle

        let killedByUs = KilledByUsFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startCapturingProcess(
                    process, killedByUs: killedByUs, timeout: timeout,
                    capture: CaptureTarget(fileHandle: fileHandle, tempURL: tempURL),
                    continuation: continuation
                )
            }
        } onCancel: {
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier)
        }
    }

    private func startProcess(
        _ process: Process,
        killedByUs: KilledByUsFlag,
        timeout: Double,
        continuation: CheckedContinuation<Int32, any Error>
    ) {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier)
        }

        process.terminationHandler = { proc in
            timeoutTask.cancel()
            let exitCode: Int32 = killedByUs.value ? -1 : proc.terminationStatus
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

    private func startCapturingProcess(
        _ process: Process,
        killedByUs: KilledByUsFlag,
        timeout: Double,
        capture: CaptureTarget,
        continuation: CheckedContinuation<(exitCode: Int32, output: String), any Error>
    ) {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier)
        }

        process.terminationHandler = { terminated in
            timeoutTask.cancel()
            capture.fileHandle.closeFile()
            let output = (try? String(contentsOf: capture.tempURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: capture.tempURL)
            let exitCode: Int32 = killedByUs.value ? -1 : terminated.terminationStatus
            continuation.resume(returning: (exitCode: exitCode, output: output))
        }

        do {
            try process.run()
            setpgid(process.processIdentifier, process.processIdentifier)
        } catch {
            timeoutTask.cancel()
            capture.fileHandle.closeFile()
            try? FileManager.default.removeItem(at: capture.tempURL)
            continuation.resume(throwing: error)
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

    private struct CaptureTarget {
        let fileHandle: FileHandle
        let tempURL: URL
    }

    private final class KilledByUsFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false

        var value: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }

        func mark() {
            lock.lock()
            flag = true
            lock.unlock()
        }
    }
}
