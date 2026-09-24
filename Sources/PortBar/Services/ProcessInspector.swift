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

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func currentDirectory(pid: Int32) -> String? {
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
    private static func arguments(pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // skip exec path
        while index < size, buffer[index] == 0 { index += 1 }  // skip padding

        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}
