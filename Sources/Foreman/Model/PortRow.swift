/// Section a process is listed under in the panel. Order of cases = display order.
enum ProcessGroup: Int, CaseIterable, Comparable, Sendable {
    case dev, dataContainer, system

    var title: String {
        switch self {
        case .dev: "Dev"
        case .dataContainer: "Database / Container"
        case .system: String(localized: "System")
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
    /// Agent that started this process, e.g. `Claude Code · Zunera`.
    var owner: String?
    /// ESTABLISHED connections into one of this process's listening ports.
    var inboundConnections = 0
    /// Process start time (seconds since epoch); also guards cleanup against PID reuse.
    var startSec: UInt64?
    var flags: Set<RowFlag> = []
    var gitBranch: String?
    /// Project (git checkout name) and the folder inside it, e.g. `Zunera` + `apps/server`.
    var project: String?
    var projectSubpath: String?
    /// Dev tool detected from argv, e.g. `Next.js`, `Vite`.
    var framework: String?
    /// Containers publishing ports through this process (OrbStack / Docker host process).
    var containers: [Container] = []

    var id: Int32 { pid }
}

/// Signs that a dev process was left behind.
enum RowFlag: Hashable, Sendable {
    /// Parent exited (re-parented to launchd): its terminal, agent or runner is gone.
    case parentExited
    /// Working directory no longer exists, e.g. its git worktree was removed.
    case folderDeleted
    /// No inbound connections and no CPU for a long time.
    case idle

    var isOrphan: Bool { self != .idle }

    var title: String {
        switch self {
        case .parentExited, .folderDeleted: String(localized: "orphan")
        case .idle: String(localized: "idle")
        }
    }

    var reason: String {
        switch self {
        case .parentExited: String(localized: "parent process exited")
        case .folderDeleted: String(localized: "folder was deleted")
        case .idle: String(localized: "no connections, no CPU")
        }
    }
}

/// Progress of a kill request for one row.
enum KillState: Equatable, Sendable {
    case terminating
    /// SIGTERM grace period elapsed and the process is still alive.
    case needsForce
    case failed(String)
}
