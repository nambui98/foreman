import AppKit
import Foundation
import Observation

/// Owns the refresh loop and kill actions; the single source of truth for the UI.
@MainActor
@Observable
final class PortMonitor {
    static let openInterval: Duration = .seconds(2)
    static let closedInterval: Duration = .seconds(15)

    private(set) var rows: [PortRow] = []
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?
    private(set) var killStates: [Int32: KillState] = [:]
    private(set) var isPanelOpen = false
    private(set) var agents: [AgentRow] = []
    private(set) var agentStates: [Int32: KillState] = [:]

    var devCount: Int { rows.count(where: { $0.group == .dev }) }

    private var sampler = CPUSampler()
    private var agentSampler = CPUSampler()
    private var detectorCache = AgentDetector.Cache()
    let agentController = AgentController(defaults: .standard)
    private var isRefreshing = false
    private var refreshRequested = false
    private var loop: Task<Void, Never>?
    private let killer = ProcessKiller()
    private let currentUID = getuid()
    private let home = NSHomeDirectory()

    func start() {
        guard loop == nil else { return }
        restartLoop()
    }

    /// Faster refresh while the panel is visible; refreshes immediately on open.
    func setPanelOpen(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        restartLoop()
    }

    /// Coalesces overlapping calls: a refresh requested while one is running runs once afterwards,
    /// so lsof is never spawned twice concurrently and CPU samples keep sane wall-clock deltas.
    func refresh() async {
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshRequested = false
            await refreshOnce()
        } while refreshRequested
    }

    /// Everything gathered off the main actor in one pass.
    private struct Snapshot: Sendable {
        let table: ProcessTable
        let agents: [AgentProcess]
        let usage: [Int32: AgentTreeUsage]
        let portDetails: [Int32: ProcessDetails]
        let cache: AgentDetector.Cache
    }

    private func refreshOnce() async {
        do {
            let sockets = try await PortScanner.scan()
            let pids = Set(sockets.map(\.pid))
            let uid = currentUID
            let cache = detectorCache
            let snapshot = await Task.detached(priority: .utility) {
                Self.collect(portPids: pids, currentUID: uid, cache: cache)
            }.value
            detectorCache = snapshot.cache

            var cpu: [Int32: Double] = [:]
            for (pid, info) in snapshot.portDetails {
                if let cpuNs = info.cpuTimeNs,
                   let percent = sampler.percent(pid: pid, cpuNs: cpuNs, wallNs: info.sampledAtNs) {
                    cpu[pid] = percent
                }
            }
            sampler.prune(keeping: pids)

            let agentPids = Set(snapshot.agents.map(\.pid))
            agentController.reconcile(table: snapshot.table, livePids: agentPids)
            var agentCPU: [Int32: Double] = [:]
            for (pid, tree) in snapshot.usage {
                agentCPU[pid] = agentSampler.percent(pid: pid, cpuNs: tree.cpuTimeNs, wallNs: tree.sampledAtNs)
            }
            agentSampler.prune(keeping: agentPids)
            agents = AgentRowBuilder.rows(
                agents: snapshot.agents, usage: snapshot.usage, cpuPercent: agentCPU,
                paused: Set(agentController.paused.keys))

            rows = RowBuilder.rows(
                sockets: sockets, details: snapshot.portDetails, cpuPercent: cpu, currentUID: currentUID,
                home: home,
                owners: AgentRowBuilder.owners(portPids: pids, table: snapshot.table, agents: agents))
            // Forget kill state for processes that are gone.
            killStates = killStates.filter { pids.contains($0.key) }
            agentStates = agentStates.filter { agentPids.contains($0.key) }
            lastError = nil
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private nonisolated static func collect(
        portPids: Set<Int32>, currentUID: UInt32, cache: AgentDetector.Cache
    ) -> Snapshot {
        let table = ProcessTable.snapshot()
        var cache = cache
        let agents = AgentDetector.agents(
            in: table, currentUID: currentUID, cache: &cache,
            path: ProcessInspector.executablePath(pid:), arguments: ProcessInspector.arguments(pid:))
        var usage: [Int32: AgentTreeUsage] = [:]
        for agent in agents {
            let members = table.descendants(of: agent.pid)
            var tree = AgentTreeUsage(childCount: members.count, cwd: ProcessInspector.currentDirectory(pid: agent.pid))
            for pid in [agent.pid] + members {
                guard let sample = ProcessInspector.usage(pid: pid) else { continue }
                tree.memoryBytes += sample.memoryBytes
                tree.cpuTimeNs += sample.cpuTimeNs
            }
            tree.sampledAtNs = DispatchTime.now().uptimeNanoseconds
            usage[agent.pid] = tree
        }
        let portDetails = Dictionary(uniqueKeysWithValues: portPids.map { ($0, ProcessInspector.details(pid: $0)) })
        return Snapshot(table: table, agents: agents, usage: usage, portDetails: portDetails, cache: cache)
    }

    // MARK: Agents

    // Actions take a fresh snapshot (~3ms): the last refresh can be up to 15s old and still list
    // processes that have exited since.

    func pause(_ agent: AgentRow) async {
        agentController.pause(agentPid: agent.pid, table: .snapshot())
        await refresh()
    }

    func resume(_ agent: AgentRow) async {
        agentController.resume(agentPid: agent.pid)
        await refresh()
    }

    /// `name (PID)` of every process a stop will signal, agent first.
    func stopPreview(_ agent: AgentRow) -> [String] {
        agentController.stopTargets(agentPid: agent.pid, table: .snapshot()).map { "\($0.1) (\($0.0.pid))" }
    }

    func stop(_ agent: AgentRow, force: Bool = false) async {
        agentStates[agent.pid] = .terminating
        switch await agentController.stop(agentPid: agent.pid, table: .snapshot(), force: force) {
        case .exited, .notFound: agentStates[agent.pid] = nil
        case .stillRunning: agentStates[agent.pid] = .needsForce
        case .notPermitted: agentStates[agent.pid] = .failed("Không đủ quyền")
        case .refused(let reason): agentStates[agent.pid] = .failed(reason)
        }
        await refresh()
    }

    func dismissAgentError(pid: Int32) {
        if case .failed = agentStates[pid] { agentStates[pid] = nil }
    }

    /// SIGTERM (or SIGKILL when `force`) the row's process or its whole group.
    func kill(_ row: PortRow, wholeGroup: Bool = false, force: Bool = false) async {
        killStates[row.pid] = .terminating
        let outcome = force
            ? await killer.forceKill(pid: row.pid, wholeGroup: wholeGroup)
            : await killer.terminate(pid: row.pid, wholeGroup: wholeGroup)

        switch outcome {
        case .exited, .notFound: killStates[row.pid] = nil
        case .stillRunning: killStates[row.pid] = .needsForce
        case .notPermitted: killStates[row.pid] = .failed("Không đủ quyền để dừng tiến trình này")
        case .refused(let reason): killStates[row.pid] = .failed(reason)
        }
        await refresh()
    }

    func fail(pid: Int32, _ message: String) {
        killStates[pid] = .failed(message)
    }

    func dismissError(pid: Int32) {
        if case .failed = killStates[pid] { killStates[pid] = nil }
    }

    private func restartLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.isPanelVisible ? Self.openInterval : Self.closedInterval)
            }
        }
    }

    /// `onAppear`/`onDisappear` of MenuBarExtra content is not guaranteed to fire on every toggle,
    /// so the fast cadence also requires an actually visible window besides the status item.
    private var isPanelVisible: Bool {
        isPanelOpen && NSApp.windows.contains { $0.isVisible && !($0.className.contains("StatusBar")) }
    }
}
