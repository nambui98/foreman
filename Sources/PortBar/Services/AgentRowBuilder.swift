/// Tree-level totals gathered off the main actor for one agent.
struct AgentTreeUsage: Sendable, Equatable {
    var memoryBytes: UInt64 = 0
    var cpuTimeNs: UInt64 = 0
    var sampledAtNs: UInt64 = 0
    var childCount = 0
    var cwd: String?
    var gitBranch: String?
}

enum AgentRowBuilder {
    /// Tree CPU at or above this counts as "working". Idle Claude Code sessions measured
    /// 0–8.5% (TUI timers), so anything lower marks every session as busy.
    static let workingThreshold = 10.0

    static func rows(
        agents: [AgentProcess], usage: [Int32: AgentTreeUsage], cpuPercent: [Int32: Double], paused: Set<Int32>
    ) -> [AgentRow] {
        agents.map { agent in
            let tree = usage[agent.pid]
            let cpu = cpuPercent[agent.pid]
            let status: AgentStatus = paused.contains(agent.pid) ? .paused
                : (cpu ?? 0) >= workingThreshold ? .working : .idle
            return AgentRow(
                pid: agent.pid, kind: agent.kind, cwd: tree?.cwd, host: agent.host, tty: agent.tty,
                startSec: agent.startSec, status: status, cpuPercent: cpu, memoryBytes: tree?.memoryBytes,
                childCount: tree?.childCount ?? 0, teamMember: agent.teamMember,
                terminal: agent.terminal, gitBranch: tree?.gitBranch)
        }
        .sorted { ($0.status, UInt64.max - ($0.memoryBytes ?? 0), $0.pid) < ($1.status, UInt64.max - ($1.memoryBytes ?? 0), $1.pid) }
    }

    /// Owning agent of each port process: the process itself or its nearest agent ancestor.
    static func owners(portPids: Set<Int32>, table: ProcessTable, agents: [AgentRow]) -> [Int32: String] {
        let labels = Dictionary(agents.map { ($0.pid, $0.label) }, uniquingKeysWith: { first, _ in first })
        var result: [Int32: String] = [:]
        for pid in portPids {
            if let owner = ([pid] + table.ancestors(of: pid)).first(where: { labels[$0] != nil }) {
                result[pid] = labels[owner]
            }
        }
        return result
    }
}
