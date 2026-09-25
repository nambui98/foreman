/// Point-in-time facts about a process, read through libproc/sysctl.
/// Any field may be nil when the kernel refuses access (other users, root).
struct ProcessDetails: Sendable, Equatable {
    let pid: Int32
    var ppid: Int32?
    var pgid: Int32?
    var uid: UInt32?
    var executablePath: String?
    var cwd: String?
    var arguments: [String] = []
    /// Physical footprint in bytes — the value Activity Monitor shows as "Memory".
    var memoryBytes: UInt64?
    /// Total user + system CPU time in nanoseconds.
    var cpuTimeNs: UInt64?
    /// Monotonic timestamp (ns) taken when `cpuTimeNs` was read.
    var sampledAtNs: UInt64 = 0
    /// Branch of the git checkout containing `cwd`, if any.
    var gitBranch: String?
}
