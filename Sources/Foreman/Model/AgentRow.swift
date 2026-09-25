import Foundation

/// Case order = sort order in the Agents tab: agents that need the user first.
enum AgentStatus: Int, Comparable, Sendable {
    case waiting, working, idle, paused

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .waiting: String(localized: "Waiting for you")
        case .working: String(localized: "Working")
        case .idle: String(localized: "Idle")
        case .paused: String(localized: "Paused")
        }
    }
}

enum AgentStatusSource: Sendable {
    /// Orca's hook-derived state for the agent's pane.
    case orca
    /// Claude Code's own session file.
    case claude
    /// Estimated from process-tree CPU.
    case cpu
}

/// One agent in the Agents tab, with totals over its whole process tree.
struct AgentRow: Identifiable, Sendable, Equatable {
    let pid: Int32
    let kind: AgentKind
    let cwd: String?
    let host: String?
    let tty: String?
    let startSec: UInt64
    let status: AgentStatus
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    /// Descendant count (tool shells, MCP servers, dev servers…).
    let childCount: Int
    var teamMember: String? = nil
    var terminal: TerminalLocator? = nil
    var gitBranch: String? = nil
    /// Git checkout name and the folder inside it, e.g. `Zunera` + `apps/server`.
    var project: String? = nil
    var projectSubpath: String? = nil
    /// State reported by Orca for the agent's pane, when it runs in Orca.
    var orcaState: OrcaAgentState? = nil
    /// Where `status` came from, for the status dot's tooltip.
    var statusSource: AgentStatusSource = .cpu
    /// Claude Code session id (links the agent to its transcript).
    var claudeSessionId: String? = nil
    /// Short task title of the agent's terminal tab (Orca), e.g. `Fix login redirect`.
    var taskTitle: String? = nil

    var id: Int32 { pid }

    /// `Claude Code · Zunera` — also used as the owner label on port rows.
    var label: String {
        let project = cwd.flatMap { $0.split(separator: "/").last.map(String.init) }
        return [kind.displayName, teamMember, project].compactMap { $0 }.joined(separator: " · ")
    }
}
