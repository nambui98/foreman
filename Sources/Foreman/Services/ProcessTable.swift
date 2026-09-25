import Darwin

/// The facts about one process needed to walk process trees.
struct ProcessEntry: Sendable, Equatable {
    let pid: Int32
    let ppid: Int32
    let pgid: Int32
    let uid: UInt32
    /// Kernel process name. For some CLIs this is not the command name
    /// (native Claude Code runs as `~/.local/share/claude/versions/2.1.281`).
    let name: String
    /// Start time (seconds since epoch) — identifies a process across PID reuse.
    let startSec: UInt64
    let flags: UInt32
    let ttyDevice: UInt32
}

/// Snapshot of every readable process with parent → children index.
struct ProcessTable: Sendable {
    let entries: [Int32: ProcessEntry]
    let children: [Int32: [Int32]]

    init(entries: [ProcessEntry]) {
        self.entries = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        children = Dictionary(grouping: entries.filter { $0.pid != $0.ppid }, by: \.ppid).mapValues { $0.map(\.pid) }
    }

    /// ~2–3 ms for ~750 processes. Processes of other users (EPERM) are skipped.
    static func snapshot() -> ProcessTable {
        let capacity = 16_384
        var pids = [pid_t](repeating: 0, count: capacity)
        // Returns the number of PIDs (not bytes), like proc_listpgrppids.
        let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        var entries: [ProcessEntry] = []
        entries.reserveCapacity(Int(max(count, 0)))
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            if let info = ProcessInspector.bsdInfo(pid: pid) {
                entries.append(ProcessEntry(
                    pid: pid, ppid: Int32(info.pbi_ppid), pgid: Int32(info.pbi_pgid), uid: info.pbi_uid,
                    name: ProcessInspector.name(of: info), startSec: info.pbi_start_tvsec,
                    flags: info.pbi_flags, ttyDevice: info.e_tdev))
            } else if let entry = kinfoEntry(pid: pid) {
                // libproc refuses other users' processes (e.g. root `login` between a terminal app
                // and its shell); sysctl still exposes the parent link, which keeps chains intact.
                entries.append(entry)
            }
        }
        return ProcessTable(entries: entries)
    }

    private static func kinfoEntry(pid: Int32) -> ProcessEntry? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return ProcessEntry(
            pid: pid, ppid: info.kp_eproc.e_ppid, pgid: info.kp_eproc.e_pgid, uid: info.kp_eproc.e_ucred.cr_uid,
            name: name, startSec: UInt64(info.kp_proc.p_un.__p_starttime.tv_sec), flags: 0,
            ttyDevice: UInt32(bitPattern: info.kp_eproc.e_tdev))
    }

    /// All processes below `pid` (breadth-first, excluding `pid`), cycle-safe.
    func descendants(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        var seen: Set<Int32> = [pid]
        var queue = children[pid] ?? []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: children[next] ?? [])
        }
        return result
    }

    /// Parent chain of `pid`, nearest first, stopping at launchd or an unreadable parent.
    func ancestors(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        var seen: Set<Int32> = [pid]
        var current = entries[pid]?.ppid
        while let parent = current, parent > 1, seen.insert(parent).inserted {
            result.append(parent)
            current = entries[parent]?.ppid
        }
        return result
    }
}
