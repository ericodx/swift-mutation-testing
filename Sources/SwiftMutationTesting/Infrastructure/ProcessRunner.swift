import Foundation

struct ProcessRunner: Sendable {
    var postTerminationCleanup: (@Sendable (Int32) -> Void)?
    let onTimeout: @Sendable (Int32) -> Void
    var readCapturedOutput: @Sendable (URL) throws -> String = {
        String(decoding: try Data(contentsOf: $0), as: UTF8.self)
    }
    var processGroups: ProcessGroupRegistry = .shared

    private struct CaptureTarget {
        let fileHandle: FileHandle
        let tempURL: URL
    }

    private struct StopFlags {
        let killedByUs: KilledByUsFlag
        let stoppedByRule: KilledByUsFlag
    }

    private static let pollInterval: Duration = .milliseconds(100)

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

        return try await awaitTermination(of: process, killedByUs: killedByUs) { continuation in
            self.startProcess(
                process, killedByUs: killedByUs, timeout: timeout,
                continuation: continuation
            )
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
        let stoppedByRule = KilledByUsFlag()

        return try await awaitTermination(of: process, killedByUs: killedByUs) { continuation in
            self.startCapturingProcess(
                process, request: request,
                flags: StopFlags(killedByUs: killedByUs, stoppedByRule: stoppedByRule),
                capture: CaptureTarget(fileHandle: fileHandle, tempURL: tempURL),
                continuation: continuation
            )
        }
    }

    private func awaitTermination<Result: Sendable>(
        of process: Process,
        killedByUs: KilledByUsFlag,
        start: (CheckedContinuation<Result, any Error>) -> Void
    ) async throws -> Result {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(start)
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

        run(process, timeoutTask: timeoutTask, continuation: continuation) { terminated in
            killedByUs.value ? -1 : terminated.terminationStatus
        }
    }

    private func startCapturingProcess(
        _ process: Process,
        request: ProcessRequest,
        flags: StopFlags,
        capture: CaptureTarget,
        continuation: CheckedContinuation<(exitCode: Int32, output: String), any Error>
    ) {
        let timeout = request.timeout
        let stopRule = request.stopRule
        let killedByUs = flags.killedByUs
        let stoppedByRule = flags.stoppedByRule
        let timeoutTask = Task {
            let deadline = ContinuousClock.now + .seconds(timeout)

            if let stopRule {
                var watcher = OutputWatcher(url: capture.tempURL, rule: stopRule)

                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: min(Self.pollInterval, deadline - .now))

                    if watcher.sawMarker() {
                        stoppedByRule.mark()
                        onTimeout(process.processIdentifier)
                        return
                    }
                }
            } else {
                try await Task.sleep(until: deadline)
            }

            killedByUs.mark()
            onTimeout(process.processIdentifier)
        }

        let discardCapture = {
            capture.fileHandle.closeFile()
            try? FileManager.default.removeItem(at: capture.tempURL)
        }
        run(
            process, timeoutTask: timeoutTask, continuation: continuation, onLaunchFailure: discardCapture
        ) { terminated in
            capture.fileHandle.closeFile()
            let output = (try? readCapturedOutput(capture.tempURL)) ?? ""
            try? FileManager.default.removeItem(at: capture.tempURL)
            let exitCode: Int32
            if stoppedByRule.value, let stopRule {
                exitCode = stopRule.exitCode
            } else {
                exitCode = killedByUs.value ? -1 : terminated.terminationStatus
            }
            return (exitCode: exitCode, output: output)
        }
    }

    private func run<Result: Sendable>(
        _ process: Process,
        timeoutTask: Task<Void, any Error>,
        continuation: CheckedContinuation<Result, any Error>,
        onLaunchFailure: () -> Void = {},
        result: @escaping @Sendable (Process) -> Result
    ) {
        process.terminationHandler = { [processGroups] terminated in
            processGroups.deregister(terminated.processIdentifier)
            timeoutTask.cancel()
            postTerminationCleanup?(terminated.processIdentifier)
            continuation.resume(returning: result(terminated))
        }

        do {
            try Task.checkCancellation()
            try process.run()
            Self.checkOwnGroup(process.processIdentifier)
            track(process)
            if Task.isCancelled {
                onTimeout(process.processIdentifier)
            }
        } catch {
            timeoutTask.cancel()
            onLaunchFailure()
            continuation.resume(throwing: error)
        }
    }

    private func track(_ process: Process) {
        Self.track(process.processIdentifier, isRunning: { process.isRunning }, in: processGroups)
    }

    static func checkOwnGroup(
        _ pid: pid_t,
        groupOf: (pid_t) -> pid_t = getpgid,
        warning: OnceWarning = groupWarning
    ) {
        let group = groupOf(pid)
        guard group >= 0, group != pid else { return }
        warning(
            "Warning: process \(pid) does not lead its own process group, "
                + "so a timeout or an interrupt may leave its child processes running"
        )
    }

    private static let groupWarning = OnceWarning()

    static func track(_ pid: pid_t, isRunning: () -> Bool, in processGroups: ProcessGroupRegistry) {
        processGroups.register(pid)
        if !isRunning() {
            processGroups.deregister(pid)
        }
    }
}
