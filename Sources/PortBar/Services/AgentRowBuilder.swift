import Foundation

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

    /// Orca says "working" but no hook event arrived for this long and the tree is quiet: the turn was
    /// interrupted (Esc sends no Stop hook), so the agent is idle.
    static let orcaStaleAfter: TimeInterval = 600

    static func rows(
        agents: [AgentProcess], usage: [Int32: AgentTreeUsage], cpuPercent: [Int32: Double], paused: Set<Int32>,
        orca: [String: OrcaAgentState] = [:], now: Date = Date()
    ) -> [AgentRow] {
        agents.map { agent in
            let tree = usage[agent.pid]
            let cpu = cpuPercent[agent.pid]
            let orcaState = agent.orcaPaneKey.flatMap { orca[$0] }
            return AgentRow(
                pid: agent.pid, kind: agent.kind, cwd: tree?.cwd, host: agent.host, tty: agent.tty,
                startSec: agent.startSec,
                status: status(paused: paused.contains(agent.pid), orca: orcaState, cpuPercent: cpu, now: now),
                cpuPercent: cpu, memoryBytes: tree?.memoryBytes,
                childCount: tree?.childCount ?? 0, teamMember: agent.teamMember,
                terminal: agent.terminal, gitBranch: tree?.gitBranch, orcaState: orcaState)
        }
        .sorted { ($0.status, UInt64.max - ($0.memoryBytes ?? 0), $0.pid) < ($1.status, UInt64.max - ($1.memoryBytes ?? 0), $1.pid) }
    }

    /// Orca's hook-derived state when available, else tree CPU (which misses model waits).
    static func status(paused: Bool, orca: OrcaAgentState?, cpuPercent: Double?, now: Date) -> AgentStatus {
        if paused { return .paused }
        let busyCPU = (cpuPercent ?? 0) >= workingThreshold
        guard let orca else { return busyCPU ? .working : .idle }
        switch orca.phase {
        case .blocked:
            return .waiting
        case .working:
            let stale = now.timeIntervalSince(orca.lastEventAt) > orcaStaleAfter
            return stale && !busyCPU ? .idle : .working
        case .done, .idle:
            // A dev server left running in the tree keeps CPU up; Orca knows the turn is over.
            return .idle
        }
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
