import Foundation

enum ProcessTree {

    static func descendants(of pid: Int32, sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32] {
        descendantEntries(of: pid, sysctl: sysctl).map(\.pid)
    }

    static func detachedDescendants(of pid: Int32, sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32] {
        descendantEntries(of: pid, sysctl: sysctl).filter { $0.groupID != pid }.map(\.pid)
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func all(sysctl: SystemCalls.Sysctl = Darwin.sysctl) -> [Int32] {
        snapshot(sysctl: sysctl).map(\.pid).filter { $0 > 1 }
    }

    // MARK: - Private

    private typealias Entry = (pid: Int32, parentPID: Int32, groupID: Int32)

    private static let snapshotAttempts = 3

    private static func descendantEntries(of pid: Int32, sysctl: SystemCalls.Sysctl) -> [Entry] {
        guard pid > 1 else { return [] }

        var childrenByParent: [Int32: [Entry]] = [:]
        for entry in snapshot(sysctl: sysctl) where entry.pid > 1 {
            childrenByParent[entry.parentPID, default: []].append(entry)
        }

        var found: [Entry] = []
        var seen: Set<Int32> = [pid]
        var pending = childrenByParent[pid] ?? []

        while let next = pending.popLast() {
            guard seen.insert(next.pid).inserted else { continue }
            found.append(next)
            pending.append(contentsOf: childrenByParent[next.pid] ?? [])
        }

        return found
    }

    private static func snapshot(sysctl: SystemCalls.Sysctl) -> [Entry] {
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
                    (
                        pid: procs[$0].kp_proc.p_pid,
                        parentPID: procs[$0].kp_eproc.e_ppid,
                        groupID: procs[$0].kp_eproc.e_pgid
                    )
                }
            }

            guard errno == ENOMEM else { return [] }
        }

        return []
    }
}
