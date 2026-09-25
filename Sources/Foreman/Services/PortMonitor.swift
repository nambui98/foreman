import AppKit
import Foundation
import Observation

/// Owns the refresh loop and kill actions; the single source of truth for the UI.
@MainActor
@Observable
final class PortMonitor {
    static let openInterval: Duration = .seconds(2)
    static let closedInterval: Duration = .seconds(15)
    /// Agent-only passes (process table, no lsof) while the CPU fallback times a working stretch.
    static let agentInterval: Duration = .seconds(3)

    private(set) var rows: [PortRow] = []
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?
    private(set) var killStates: [Int32: KillState] = [:]
    private(set) var isPanelOpen = false
    private(set) var agents: [AgentRow] = []
    private(set) var agentStates: [Int32: KillState] = [:]
    private(set) var containers: [Container] = []
    private(set) var containerStates: [String: KillState] = [:]
    private var lastDockerScan: ContinuousClock.Instant?
    /// `docker ps` costs ~0.06s CPU: often while the panel is open, rarely in the background.
    static let dockerOpenInterval: Duration = .seconds(5)
    static let dockerClosedInterval: Duration = .seconds(60)

    var devCount: Int { rows.count(where: { $0.group == .dev }) }
    var devMemoryBytes: UInt64 { rows.filter { $0.group == .dev }.compactMap(\.memoryBytes).reduce(0, +) }

    private var sampler = CPUSampler()
    private var agentSampler = CPUSampler()
    private var detectorCache = AgentDetector.Cache()
    private var branchCache = GitBranch.Cache()
    private var orcaReader = OrcaStatusReader()
    private var claudeReader = ClaudeSessionReader()
    /// Orca terminal handle → task title; fetched only while the panel is open.
    private var taskTitles: [String: String] = [:]
    private var lastTitleFetch: ContinuousClock.Instant?
    static let titleInterval: Duration = .seconds(10)
    let agentController = AgentController(defaults: .standard)
    private var isRefreshing = false
    private var refreshRequested = false
    private var loop: Task<Void, Never>?
    private let killer = ProcessKiller()
    private let currentUID = getuid()
    private let home = NSHomeDirectory()
    private var lastFullRefresh: ContinuousClock.Instant?
    let events: AgentEventCenter
    let keepAwake = KeepAwake()
    /// Mirrors `keepAwake.isActive` for the UI.
    private(set) var isKeepingAwake = false
    private let settings: AppSettings
    private var flagger = RowFlagger()

    /// Dev rows flagged as orphan or idle, offered by the "Clean up" button.
    var cleanupCandidates: [PortRow] { rows.filter { !$0.flags.isEmpty && $0.isKillable } }

    init(settings: AppSettings) {
        self.settings = settings
        events = AgentEventCenter(settings: settings)
    }

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
            await refreshOnce(includePorts: true)
        } while refreshRequested
    }

    /// Agents only (~3ms process-table pass, no lsof); skipped while a full refresh runs.
    private func refreshAgents() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await refreshOnce(includePorts: false)
        isRefreshing = false
        // A full refresh asked for meanwhile (user action, hook event) must not be lost.
        if refreshRequested { await refresh() }
    }

    /// Everything gathered off the main actor in one pass.
    private struct Snapshot: Sendable {
        let table: ProcessTable
        let agents: [AgentProcess]
        let usage: [Int32: AgentTreeUsage]
        let portDetails: [Int32: ProcessDetails]
        let cache: AgentDetector.Cache
        let branches: GitBranch.Cache
        let orcaReader: OrcaStatusReader
        let orcaStates: [String: OrcaAgentState]
        let claudeReader: ClaudeSessionReader
        let claudeSessions: [Int32: ClaudeSession]
    }

    private func refreshOnce(includePorts: Bool) async {
        do {
            let scan = includePorts ? try await PortScanner.scan() : LsofScan()
            let sockets = scan.listening
            let pids = Set(sockets.map(\.pid))
            let uid = currentUID
            let cache = detectorCache
            let branches = branchCache
            let orcaReader = orcaReader
            let claudeReader = claudeReader
            let snapshot = await Task.detached(priority: .utility) {
                Self.collect(
                    portPids: pids, currentUID: uid, cache: cache, branches: branches, orcaReader: orcaReader,
                    claudeReader: claudeReader)
            }.value
            detectorCache = snapshot.cache
            branchCache = snapshot.branches
            self.orcaReader = snapshot.orcaReader
            self.claudeReader = snapshot.claudeReader
            if includePorts { await refreshTaskTitlesIfDue() }
            updateAgents(from: snapshot)
            guard includePorts else { return }

            await refreshContainersIfDue(hostPresent: sockets.contains { DockerScanner.hostProcessNames.contains($0.command) })

            var cpu: [Int32: Double] = [:]
            for (pid, info) in snapshot.portDetails {
                if let cpuNs = info.cpuTimeNs,
                   let percent = sampler.percent(pid: pid, cpuNs: cpuNs, wallNs: info.sampledAtNs) {
                    cpu[pid] = percent
                }
            }
            sampler.prune(keeping: pids)

            let entries = snapshot.table.entries
            let built = RowBuilder.rows(
                sockets: sockets, details: snapshot.portDetails, cpuPercent: cpu, currentUID: currentUID,
                home: home,
                owners: AgentRowBuilder.owners(portPids: pids, table: snapshot.table, agents: agents),
                established: scan.established,
                startSec: entries.compactMapValues { pids.contains($0.pid) ? $0.startSec : nil },
                containers: containers)
            rows = flagger.apply(
                to: built, parentPid: entries.compactMapValues { pids.contains($0.pid) ? $0.ppid : nil },
                now: UInt64(Date().timeIntervalSince1970), idleHours: settings.idleHours)
            // Forget kill state for processes that are gone.
            killStates = killStates.filter { pids.contains($0.key) }
            lastError = nil
            lastUpdated = Date()
            lastFullRefresh = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateAgents(from snapshot: Snapshot) {
        let agentPids = Set(snapshot.agents.map(\.pid))
        agentController.reconcile(table: snapshot.table, livePids: agentPids)
        var agentCPU: [Int32: Double] = [:]
        for (pid, tree) in snapshot.usage {
            agentCPU[pid] = agentSampler.percent(pid: pid, cpuNs: tree.cpuTimeNs, wallNs: tree.sampledAtNs)
        }
        agentSampler.prune(keeping: agentPids)
        agents = AgentRowBuilder.rows(
            agents: snapshot.agents, usage: snapshot.usage, cpuPercent: agentCPU,
            paused: Set(agentController.paused.keys), orca: snapshot.orcaStates, claude: snapshot.claudeSessions)
        .map { row in
            var row = row
            if case .orca(let handle) = row.terminal { row.taskTitle = taskTitles[handle] }
            return row
        }
        agentStates = agentStates.filter { agentPids.contains($0.key) }
        events.observe(agents: agents)
        keepAwake.update(active: settings.keepAwake && agents.contains { $0.status == .working })
        isKeepingAwake = keepAwake.isActive
    }

    private nonisolated static func collect(
        portPids: Set<Int32>, currentUID: UInt32, cache: AgentDetector.Cache, branches: GitBranch.Cache,
        orcaReader: OrcaStatusReader, claudeReader: ClaudeSessionReader
    ) -> Snapshot {
        var orcaReader = orcaReader
        let orcaStates = orcaReader.states()
        var claudeReader = claudeReader
        let claudeSessions = claudeReader.sessions()
        var branches = branches
        var folders: Set<String> = []
        let table = ProcessTable.snapshot()
        var cache = cache
        let agents = AgentDetector.agents(
            in: table, currentUID: currentUID, cache: &cache,
            path: ProcessInspector.executablePath(pid:), arguments: ProcessInspector.arguments(pid:))
        var usage: [Int32: AgentTreeUsage] = [:]
        for agent in agents {
            let members = table.descendants(of: agent.pid)
            let cwd = ProcessInspector.currentDirectory(pid: agent.pid)
            var tree = AgentTreeUsage(
                childCount: members.count, cwd: cwd, gitBranch: cwd.flatMap { branches.branch(cwd: $0) })
            if let cwd { folders.insert(cwd) }
            for pid in [agent.pid] + members {
                guard let sample = ProcessInspector.usage(pid: pid) else { continue }
                tree.memoryBytes += sample.memoryBytes
                tree.cpuTimeNs += sample.cpuTimeNs
            }
            tree.sampledAtNs = DispatchTime.now().uptimeNanoseconds
            usage[agent.pid] = tree
        }
        let portDetails = Dictionary(uniqueKeysWithValues: portPids.map { pid in
            var details = ProcessInspector.details(pid: pid)
            details.repository = details.cwd.flatMap { branches.repository(cwd: $0) }
            details.gitBranch = details.repository?.branch
            if let cwd = details.cwd { folders.insert(cwd) }
            return (pid, details)
        })
        // Agent-only passes see no port folders; keep those entries until the next full pass.
        if !portPids.isEmpty { branches.prune(keeping: folders) }
        return Snapshot(
            table: table, agents: agents, usage: usage, portDetails: portDetails, cache: cache, branches: branches,
            orcaReader: orcaReader, orcaStates: orcaStates, claudeReader: claudeReader, claudeSessions: claudeSessions)
    }

    // MARK: Agent events

    /// A `foreman://agent-event` URL from an agent hook. The pid is the hook shell's parent: the
    /// agent itself or a wrapper below it, so it is matched against the agent and its ancestors.
    func handleAgentEvent(_ url: URL) async {
        guard let (kind, pid) = AgentEventURL.parse(url) else { return }
        var agent = agent(containing: pid)
        // An agent started since the last refresh is not listed yet. Any local process can open
        // foreman:// URLs, so the retry is a cheap agent-only pass and at most one per interval.
        if agent == nil, ContinuousClock.now - lastEventLookup >= Self.eventLookupInterval {
            lastEventLookup = .now
            await refreshAgentsAfterCurrent()
            agent = self.agent(containing: pid)
        }
        events.handleHook(kind, agent: agent)
    }

    static let eventLookupInterval: Duration = .seconds(2)
    private var lastEventLookup = ContinuousClock.now - .seconds(60)

    /// Waits for a running refresh (up to 3s) instead of skipping, then does an agent-only pass.
    private func refreshAgentsAfterCurrent() async {
        let deadline = ContinuousClock.now + .seconds(3)
        while isRefreshing, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await refreshAgents()
    }

    /// The listed agent that is `pid` or one of its ancestors, matched by start time as well so a
    /// recycled PID is never mistaken for an agent that exited.
    private func agent(containing pid: Int32) -> AgentRow? {
        let table = ProcessTable.snapshot()
        for id in [pid] + table.ancestors(of: pid) {
            if let agent = agents.first(where: { $0.pid == id }), table.entries[id]?.startSec == agent.startSec {
                return agent
            }
        }
        return nil
    }

    /// Notification click: focus the agent's terminal if the same process is still running.
    func openAgent(_ member: AgentController.Member) async {
        guard let agent = agents.first(where: { $0.pid == member.pid && $0.startSec == member.startSec }) else {
            return
        }
        await jumpToTerminal(agent)
    }

    /// Focuses the agent's terminal tab; a failure is shown on the row (the host app still comes forward).
    func jumpToTerminal(_ agent: AgentRow) async {
        guard let locator = agent.terminal else { return }
        if let message = await TerminalJumper.jump(to: locator) {
            agentStates[agent.pid] = .failed(message)
        } else if case .failed = agentStates[agent.pid] {
            agentStates[agent.pid] = nil
        }
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
        case .notPermitted: agentStates[agent.pid] = .failed(String(localized: "Not permitted"))
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

        killStates[row.pid] = Self.state(after: outcome)
        await refresh()
    }

    // MARK: Task titles

    /// `orca terminal list` costs ~0.15s CPU, so titles are only refreshed while someone looks.
    private func refreshTaskTitlesIfDue() async {
        guard isPanelVisible, agents.contains(where: { if case .orca = $0.terminal { true } else { false } }) else {
            return
        }
        if let last = lastTitleFetch, ContinuousClock.now - last < Self.titleInterval { return }
        lastTitleFetch = .now
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalJumper.orcaBundleID) else {
            return
        }
        let cli = app.appending(path: "Contents/Resources/bin/orca")
        if let titles = await Task.detached(priority: .utility, operation: { OrcaTerminalTitles.list(orcaCLI: cli) }).value {
            taskTitles = titles
        }
    }

    // MARK: Containers

    /// Re-lists containers when a Docker/OrbStack host process holds ports and the scan is due.
    private func refreshContainersIfDue(hostPresent: Bool, force: Bool = false) async {
        guard hostPresent else {
            containers = []
            return
        }
        let interval = isPanelVisible ? Self.dockerOpenInterval : Self.dockerClosedInterval
        if !force, let last = lastDockerScan, ContinuousClock.now - last < interval { return }
        lastDockerScan = .now
        if let listed = await Task.detached(priority: .utility, operation: { DockerScanner.list() }).value {
            containers = listed
            containerStates = containerStates.filter { id, _ in listed.contains { $0.id == id } }
        }
    }

    func perform(_ action: DockerScanner.Action, on container: Container) async {
        containerStates[container.id] = .terminating
        let id = container.id
        let ok = await Task.detached(priority: .userInitiated) { DockerScanner.perform(action, containerID: id) }.value
        containerStates[container.id] = ok ? nil : .failed(String(localized: "docker \(action.rawValue) failed"))
        lastDockerScan = nil
        await refresh()
    }

    func dismissContainerError(id: String) {
        if case .failed = containerStates[id] { containerStates[id] = nil }
    }

    /// SIGTERMs the selected leftover processes in parallel, then refreshes once. A row whose PID
    /// now belongs to a different process (start time changed) is skipped.
    func cleanUp(_ targets: [PortRow]) async {
        let killer = killer
        await withTaskGroup(of: (Int32, KillOutcome).self) { group in
            for row in targets where row.isKillable && Self.isSameProcess(row) {
                killStates[row.pid] = .terminating
                group.addTask { (row.pid, await killer.terminate(pid: row.pid, wholeGroup: false)) }
            }
            for await (pid, outcome) in group {
                killStates[pid] = Self.state(after: outcome)
            }
        }
        await refresh()
    }

    /// The row's PID still belongs to the process that was listed (start time unchanged).
    nonisolated static func isSameProcess(_ row: PortRow) -> Bool {
        guard let started = row.startSec else { return false }
        return ProcessInspector.bsdInfo(pid: row.pid)?.pbi_start_tvsec == started
    }

    private static func state(after outcome: KillOutcome) -> KillState? {
        switch outcome {
        case .exited, .notFound: nil
        case .stillRunning: .needsForce
        case .notPermitted: .failed(String(localized: "Not permitted to stop this process"))
        case .refused(let reason): .failed(reason)
        }
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
                if self.isFullRefreshDue {
                    await self.refresh()
                } else {
                    await self.refreshAgents()
                }
                try? await Task.sleep(for: self.nextTick)
            }
        }
    }

    /// lsof runs at the panel/closed cadence even when agent passes tick faster.
    private var isFullRefreshDue: Bool {
        guard !isPanelVisible, let last = lastFullRefresh else { return true }
        return ContinuousClock.now - last >= Self.closedInterval - .milliseconds(500)
    }

    private var nextTick: Duration {
        if isPanelVisible { return Self.openInterval }
        return events.needsFastPolling ? Self.agentInterval : Self.closedInterval
    }

    /// `onAppear`/`onDisappear` of MenuBarExtra content is not guaranteed to fire on every toggle,
    /// so the fast cadence also requires an actually visible window besides the status item.
    private var isPanelVisible: Bool {
        isPanelOpen && NSApp.windows.contains { $0.isVisible && !($0.className.contains("StatusBar")) }
    }
}
