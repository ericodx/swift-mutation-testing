import Foundation

enum ProcessTree {

    static func descendants(of pid: Int32, sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32] {
        guard pid > 1 else { return [] }

        var childrenByParent: [Int32: [Int32]] = [:]
        for entry in snapshot(sysctl: sysctl) where entry.pid > 1 {
            childrenByParent[entry.parentPID, default: []].append(entry.pid)
        }

        var found: [Int32] = []
        var seen: Set<Int32> = [pid]
        var pending = childrenByParent[pid] ?? []

        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            found.append(next)
            pending.append(contentsOf: childrenByParent[next] ?? [])
        }

        return found
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func all(sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32] {
        snapshot(sysctl: sysctl).map(\.pid).filter { $0 > 1 }
    }

    // MARK: - Private

    private static let snapshotAttempts = 3

    private static func snapshot(sysctl: SystemCalls.Sysctl) -> [(pid: Int32, parentPID: Int32)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        let stride = MemoryLayout<kinfo_proc>.stride

        for _ in 0 ..< snapshotAttempts {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

            let capacity = size / stride + size / stride / 8 + 16
            var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            size = capacity * stride

            if sysctl(&mib, 4, &procs, &size, nil, 0) == 0 {
                return (0 ..< size / stride).map {
                    (pid: procs[$0].kp_proc.p_pid, parentPID: procs[$0].kp_eproc.e_ppid)
                }
            }

            guard errno == ENOMEM else { return [] }
        }

        return []
    }
}
