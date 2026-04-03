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

        let killedByUs = KilledByUsFlag()
        let sandboxPath = workingDirectoryURL.path

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startProcess(process, killedByUs: killedByUs, timeout: timeout, sandboxPath: sandboxPath, continuation: continuation)
            }
        } onCancel: {
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier, sandboxPath: sandboxPath)
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
        let sandboxPath = workingDirectoryURL.path

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.startCapturingProcess(
                    process, killedByUs: killedByUs, timeout: timeout,
                    sandboxPath: sandboxPath,
                    capture: CaptureTarget(fileHandle: fileHandle, tempURL: tempURL),
                    continuation: continuation
                )
            }
        } onCancel: {
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier, sandboxPath: sandboxPath)
        }
    }

    private func startProcess(
        _ process: Process,
        killedByUs: KilledByUsFlag,
        timeout: Double,
        sandboxPath: String,
        continuation: CheckedContinuation<Int32, any Error>
    ) {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier, sandboxPath: sandboxPath)
        }

        process.terminationHandler = { proc in
            timeoutTask.cancel()
            kill(-proc.processIdentifier, SIGKILL)
            killEscapedChildren(sandboxPath: sandboxPath)
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
        sandboxPath: String,
        capture: CaptureTarget,
        continuation: CheckedContinuation<(exitCode: Int32, output: String), any Error>
    ) {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            killedByUs.mark()
            terminateProcessGroup(pid: process.processIdentifier, sandboxPath: sandboxPath)
        }

        process.terminationHandler = { terminated in
            timeoutTask.cancel()
            kill(-terminated.processIdentifier, SIGKILL)
            killEscapedChildren(sandboxPath: sandboxPath)
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

    private func terminateProcessGroup(pid: Int32, sandboxPath: String = "") {
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        Task {
            try? await Task.sleep(for: .seconds(5))
            kill(-pid, SIGKILL)
            killEscapedChildren(sandboxPath: sandboxPath)
        }
    }

    private func killEscapedChildren(sandboxPath: String) {
        let sandboxName = URL(fileURLWithPath: sandboxPath).lastPathComponent
        guard sandboxName.hasPrefix("xmr-") else { return }
        guard let pathData = sandboxName.data(using: .utf8) else { return }

        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return }

        let procSize = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / procSize)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return }

        for i in 0..<(size / procSize) {
            let pid = procs[i].kp_proc.p_pid
            guard pid > 1 else { continue }

            var argSize = 0
            var argMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            guard sysctl(&argMib, 3, nil, &argSize, nil, 0) == 0, argSize > 0 else { continue }

            var argBuf = [UInt8](repeating: 0, count: argSize)
            guard sysctl(&argMib, 3, &argBuf, &argSize, nil, 0) == 0 else { continue }

            if Data(argBuf[..<argSize]).range(of: pathData) != nil {
                kill(-pid, SIGKILL)
                kill(pid, SIGKILL)
            }
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
