/// Turns cumulative CPU time into a CPU% by diffing consecutive samples per PID.
/// Values above 100% are expected for multi-threaded processes (same as Activity Monitor).
struct CPUSampler {
    private var previous: [Int32: (cpuNs: UInt64, wallNs: UInt64)] = [:]

    /// Returns nil for the first sample of a PID, or when the counter went backwards (PID reused).
    mutating func percent(pid: Int32, cpuNs: UInt64, wallNs: UInt64) -> Double? {
        defer { previous[pid] = (cpuNs, wallNs) }
        guard let last = previous[pid], cpuNs >= last.cpuNs, wallNs > last.wallNs else { return nil }
        return Double(cpuNs - last.cpuNs) / Double(wallNs - last.wallNs) * 100
    }

    mutating func prune(keeping pids: Set<Int32>) {
        previous = previous.filter { pids.contains($0.key) }
    }
}
