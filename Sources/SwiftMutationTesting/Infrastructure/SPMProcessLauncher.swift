import Foundation

struct SPMProcessLauncher: Sendable, ProcessLaunching {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        let sandboxPath = workingDirectoryURL.path
        return try await makeRunner(sandboxPath: sandboxPath).launch(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        let sandboxPath = request.workingDirectoryURL.path
        return try await makeRunner(sandboxPath: sandboxPath).launchCapturing(request)
    }

    private func makeRunner(sandboxPath: String) -> ProcessRunner {
        ProcessRunner(
            postTerminationCleanup: { pid in
                kill(-pid, SIGKILL)
                killEscapedChildren(sandboxPath: sandboxPath)
            },
            onTimeout: { pid in
                guard pid > 0 else { return }
                kill(-pid, SIGTERM)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    kill(-pid, SIGKILL)
                    killEscapedChildren(sandboxPath: sandboxPath)
                }
            }
        )
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

    for index in 0 ..< (size / procSize) {
        let pid = procs[index].kp_proc.p_pid
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
