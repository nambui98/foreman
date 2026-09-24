/// Section a process is listed under in the panel. Order of cases = display order.
enum ProcessGroup: Int, CaseIterable, Comparable, Sendable {
    case dev, dataContainer, system

    var title: String {
        switch self {
        case .dev: "Dev"
        case .dataContainer: "Database / Container"
        case .system: "Hệ thống"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One process in the panel, with every TCP port it listens on.
struct PortRow: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let ports: [Int]
    let commandLine: String?
    let cwd: String?
    let executablePath: String?
    let pgid: Int32?
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let group: ProcessGroup
    /// Signals can only be delivered to processes of the current user (no privilege escalation).
    let isKillable: Bool

    var id: Int32 { pid }
}

/// Progress of a kill request for one row.
enum KillState: Equatable, Sendable {
    case terminating
    /// SIGTERM grace period elapsed and the process is still alive.
    case needsForce
    case failed(String)
}
