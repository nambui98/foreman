import Darwin
import Foundation

/// Reads process facts straight from the kernel (libproc + sysctl) — no subprocesses.
enum ProcessInspector {
    /// Multiplier from mach absolute-time ticks to nanoseconds (125/3 on Apple Silicon, 1/1 on Intel).
    /// `rusage_info` CPU times are reported in ticks, not ns.
    static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    static func details(pid: Int32) -> ProcessDetails {
        var details = ProcessDetails(pid: pid)
        if let bsd = bsdInfo(pid: pid) {
            details.ppid = Int32(bsd.pbi_ppid)
            details.pgid = Int32(bsd.pbi_pgid)
            details.uid = bsd.pbi_uid
        }
        details.executablePath = executablePath(pid: pid)
        details.cwd = currentDirectory(pid: pid)
        details.arguments = arguments(pid: pid)
        if let usage = resourceUsage(pid: pid) {
            details.memoryBytes = usage.ri_phys_footprint
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            details.cpuTimeNs = ticks &* timebase.numer / timebase.denom
        }
        details.sampledAtNs = DispatchTime.now().uptimeNanoseconds
        return details
    }

    /// Memory footprint and total CPU time (ns) only — the cheap subset used for whole process trees.
    static func usage(pid: Int32) -> (memoryBytes: UInt64, cpuTimeNs: UInt64)? {
        guard let usage = resourceUsage(pid: pid) else { return nil }
        let ticks = usage.ri_user_time &+ usage.ri_system_time
        return (usage.ri_phys_footprint, ticks &* timebase.numer / timebase.denom)
    }

    /// `ttys003` for a controlling-terminal device number, nil when the process has none.
    static func ttyName(device: UInt32) -> String? {
        guard device != UInt32.max, let name = devname(dev_t(bitPattern: device), mode_t(S_IFCHR)) else {
            return nil
        }
        return String(cString: name)
    }

    static func bsdInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    /// PIDs currently in process group `pgid`.
    static func groupMembers(pgid: Int32) -> [Int32] {
        let capacity = 1024
        var pids = [pid_t](repeating: 0, count: capacity)
        // Unlike proc_listpids, this returns the number of PIDs written, not bytes.
        let count = proc_listpgrppids(pgid, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return pids.prefix(min(Int(count), capacity)).filter { $0 > 0 }
    }

    /// Short process name (`pbi_name`, falls back to `pbi_comm`).
    static func name(of info: proc_bsdinfo) -> String {
        var info = info
        let name = withUnsafeBytes(of: &info.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if !name.isEmpty { return name }
        return withUnsafeBytes(of: &info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// True while the process exists and is not a zombie waiting to be reaped.
    static func isAlive(pid: Int32) -> Bool {
        if kill(pid, 0) != 0 && errno == ESRCH { return false }
        guard let info = bsdInfo(pid: pid) else { return true }
        return info.pbi_status != UInt32(SZOMB)
    }

    static func executablePath(pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    static func currentDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    private static func resourceUsage(pid: Int32) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage : nil
    }

    /// argv via `KERN_PROCARGS2`: [argc: Int32][exec path\0][\0 padding][argv0\0 argv1\0 …][env…].
    static func arguments(pid: Int32) -> [String] {
        processArguments(pid: pid, environmentKeys: [])?.arguments ?? []
    }

    /// Environment keys PortBar may read from other processes: enough to locate an agent's
    /// terminal tab. Everything else (tokens, secrets) is skipped while parsing and never stored.
    static let terminalEnvironmentKeys: Set<String> = [
        "TERM_PROGRAM", "ORCA_TERMINAL_HANDLE", "ORCA_PANE_KEY", "ITERM_SESSION_ID", "TERM_SESSION_ID",
    ]

    /// Values of `keys` from the process environment (same `KERN_PROCARGS2` buffer as argv).
    static func environment(pid: Int32, keys: Set<String> = terminalEnvironmentKeys) -> [String: String] {
        processArguments(pid: pid, environmentKeys: keys)?.environment ?? [:]
    }

    private static func processArguments(
        pid: Int32, environmentKeys: Set<String>
    ) -> (arguments: [String], environment: [String: String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcessArguments(buffer[..<size], environmentKeys: environmentKeys)
    }

    /// Parses a `KERN_PROCARGS2` buffer. Only environment entries named in `environmentKeys` are kept.
    static func parseProcessArguments(
        _ buffer: ArraySlice<UInt8>, environmentKeys: Set<String>
    ) -> (arguments: [String], environment: [String: String]) {
        guard buffer.count > MemoryLayout<Int32>.size else { return ([], [:]) }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        let end = buffer.endIndex
        var index = buffer.startIndex + MemoryLayout<Int32>.size
        while index < end, buffer[index] != 0 { index += 1 }  // skip exec path
        while index < end, buffer[index] == 0 { index += 1 }  // skip padding

        func nextString() -> ArraySlice<UInt8> {
            let start = index
            while index < end, buffer[index] != 0 { index += 1 }
            defer { index += 1 }
            return buffer[start..<index]
        }

        var args: [String] = []
        while args.count < argc, index < end {
            args.append(String(decoding: nextString(), as: UTF8.self))
        }

        var environment: [String: String] = [:]
        guard !environmentKeys.isEmpty else { return (args, environment) }
        while index < end {
            let entry = nextString()
            if entry.isEmpty { break }  // environment ends at the first empty string
            guard let equals = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let key = String(decoding: entry[..<equals], as: UTF8.self)
            if environmentKeys.contains(key) {
                environment[key] = String(decoding: entry[(equals + 1)...], as: UTF8.self)
            }
        }
        return (args, environment)
    }
}
