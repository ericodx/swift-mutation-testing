import Foundation

struct ProcessRunner: Sendable {
    var postTerminationCleanup: (@Sendable (Int32) -> Void)?
    let onTimeout: @Sendable (Int32) -> Void

    private struct CaptureTarget {
        let fileHandle: FileHandle
        let tempURL: URL
    }

    final class KilledByUsFlag: @unchecked Sendable {
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
                self.startProcess(
                    process, killedByUs: killedByUs, timeout: timeout,
                    continuation: continuation
                )
            }
        } onCancel: {
            killedByUs.mark()
            onTimeout(process.processIdentifier)
        }
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectoryURL

        if let environment = request.environment {
            process.environment = environment
        }

        if !request.additionalEnvironment.isEmpty {
            var env = process.environment ?? ProcessInfo.processInfo.environment
            for (key, value) in request.additionalEnvironment {
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
                    process, killedByUs: killedByUs, timeout: request.timeout,
                    capture: CaptureTarget(fileHandle: fileHandle, tempURL: tempURL),
                    continuation: continuation
                )
            }
        } onCancel: {
            killedByUs.mark()
            onTimeout(process.processIdentifier)
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
            onTimeout(process.processIdentifier)
        }

        process.terminationHandler = { proc in
            timeoutTask.cancel()
            postTerminationCleanup?(proc.processIdentifier)
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
            onTimeout(process.processIdentifier)
        }

        process.terminationHandler = { terminated in
            timeoutTask.cancel()
            postTerminationCleanup?(terminated.processIdentifier)
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

}
