import Foundation

/// Reads the kernel's process table to find what a process has spawned.
///
/// Killing a process group does not always reach everything a test run started: a child that calls
/// `setsid`, or one whose parent has already died, leaves the group and survives. Those are the
/// processes cleanup has to chase, and they can only be identified while the process that owns them
/// is still alive — once it dies they are reparented to `launchd` and nothing connects them to it
/// any more.
///
/// So the descendants are snapshotted before the kill, and the snapshot is what gets killed
/// afterwards. The alternative — searching every process on the machine for one whose arguments
/// mention the sandbox — cannot tell one mutant's test run from another's when both run in the same
/// sandbox, and killed the wrong one (issue #69).
enum ProcessTree {

    /// Every process descended from `pid`, however deeply, excluding `pid` itself.
    static func descendants(of pid: Int32) -> [Int32] {
        guard pid > 1 else { return [] }

        var childrenByParent: [Int32: [Int32]] = [:]
        for entry in snapshot() where entry.pid > 1 {
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

    // MARK: - Private

    private static func snapshot() -> [(pid: Int32, parentPID: Int32)] {
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)

        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        return (0 ..< size / stride).map {
            (pid: procs[$0].kp_proc.p_pid, parentPID: procs[$0].kp_eproc.e_ppid)
        }
    }
}
