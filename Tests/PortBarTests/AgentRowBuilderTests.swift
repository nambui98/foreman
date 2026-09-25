import Testing
@testable import PortBar

struct AgentRowBuilderTests {
    static func agent(_ pid: Int32) -> AgentProcess {
        AgentProcess(pid: pid, kind: .claude, startSec: 0, tty: "ttys001", host: "Orca")
    }

    @Test func statusPriorityAndSorting() {
        let usage: [Int32: AgentTreeUsage] = [
            1: AgentTreeUsage(memoryBytes: 100, cwd: "/Users/me/a"),
            2: AgentTreeUsage(memoryBytes: 900, cwd: "/Users/me/b"),
            3: AgentTreeUsage(memoryBytes: 500, cwd: "/Users/me/c"),
        ]
        let rows = AgentRowBuilder.rows(
            agents: [Self.agent(1), Self.agent(2), Self.agent(3)], usage: usage,
            cpuPercent: [1: 25, 2: 8.5, 3: 40], paused: [3])
        #expect(rows.map(\.pid) == [1, 2, 3])  // working, idle, paused
        #expect(rows.map(\.status) == [.working, .idle, .paused])
        #expect(rows[0].label == "Claude Code · a")
    }

    @Test func idleAgentsSortByMemoryDescending() {
        let usage: [Int32: AgentTreeUsage] = [1: AgentTreeUsage(memoryBytes: 10), 2: AgentTreeUsage(memoryBytes: 20)]
        let rows = AgentRowBuilder.rows(agents: [Self.agent(1), Self.agent(2)], usage: usage, cpuPercent: [:], paused: [])
        #expect(rows.map(\.pid) == [2, 1])
    }

    @Test func portOwnerIsNearestAgentAncestor() {
        let table = ProcessTable(entries: [entry(10, 1), entry(20, 10), entry(30, 20), entry(40, 1)])
        let agents = AgentRowBuilder.rows(
            agents: [Self.agent(10)], usage: [10: AgentTreeUsage(cwd: "/Users/me/Zunera")], cpuPercent: [:], paused: [])
        let owners = AgentRowBuilder.owners(portPids: [30, 40], table: table, agents: agents)
        #expect(owners == [30: "Claude Code · Zunera"])
    }
}
