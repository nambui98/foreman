import Foundation
import Observation

/// Turns hook events and CPU transitions into "agent finished / needs you" notices.
@MainActor
@Observable
final class AgentEventCenter {
    struct Notice: Equatable, Sendable {
        let agent: AgentController.Member
        let kind: AgentEventKind
        let title: String
        let body: String
    }

    /// Last event received from a hook, shown in Settings so the user can check the setup.
    private(set) var lastHookEvent: String?

    @ObservationIgnored var post: (Notice) -> Void = { _ in }
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var taskStart: [AgentController.Member: Date] = [:]
    /// Last hook event per agent. While hooks keep arriving (or a hooked task is open) the CPU
    /// fallback leaves that agent alone; if they stop, the fallback takes over again.
    @ObservationIgnored private var lastHook: [AgentController.Member: Date] = [:]
    @ObservationIgnored private var lastPosted: [String: Date] = [:]
    @ObservationIgnored private var tracker = StatusTransitionTracker()
    /// Previous Orca state per agent, to turn Orca's own transitions into notices.
    @ObservationIgnored private var lastOrca: [AgentController.Member: OrcaAgentState] = [:]
    @ObservationIgnored private var anyOrcaWorking = false

    /// The same notice for the same agent is dropped inside this window (hooks can fire in bursts).
    static let dedupeWindow: TimeInterval = 10
    /// A hooked agent with no open task and no hook event for this long is watched by CPU again.
    static let hookSilenceLimit: TimeInterval = 600

    init(settings: AppSettings) {
        self.settings = settings
    }

    func handleHook(_ kind: AgentEventKind, agent: AgentRow?, now: Date = Date()) {
        lastHookEvent = "\(now.formatted(date: .omitted, time: .standard)) · \(kind.rawValue) · "
            + (agent?.label ?? "không khớp agent nào")
        guard let agent else { return }
        let id = Self.identity(of: agent)
        lastHook[id] = now
        switch kind {
        case .start:
            taskStart[id] = now
        case .stop:
            let duration = taskStart.removeValue(forKey: id).map { now.timeIntervalSince($0) }
            // Without a start event (e.g. Codex notify) the task length is unknown: notify.
            if let duration, duration < settings.notifyMinWorkSec { return }
            let body = duration.map { "Xong việc sau \(Formatters.uptime(seconds: Int($0)))" } ?? "Xong việc"
            emit(Notice(agent: id, kind: .stop, title: agent.label, body: body), now: now)
        case .input:
            emit(Notice(agent: id, kind: .input, title: agent.label, body: "Đang chờ bạn trả lời"), now: now)
        }
    }

    /// Call after every agent refresh: Orca state transitions for agents running in Orca, and the
    /// CPU fallback for the rest (unless they report through Foreman hooks).
    func observe(agents: [AgentRow], now: Date = Date()) {
        let live = Set(agents.map(Self.identity(of:)))
        lastHook = lastHook.filter { live.contains($0.key) }
        taskStart = taskStart.filter { live.contains($0.key) }
        lastOrca = lastOrca.filter { live.contains($0.key) }
        observeOrca(agents: agents, now: now)
        let orcaTracked = Set(agents.filter { $0.orcaState != nil }.map(Self.identity(of:)))
        let hooked = Set(lastHook.filter { id, last in
            taskStart[id] != nil || now.timeIntervalSince(last) < Self.hookSilenceLimit
        }.keys).union(orcaTracked)
        let finished = tracker.update(
            agents.map { (Self.identity(of: $0), $0.status) }, now: now,
            minWork: settings.notifyMinWorkSec, idleDebounce: settings.cpuIdleDebounceSec, excluded: hooked)
        for id in finished {
            guard let agent = agents.first(where: { Self.identity(of: $0) == id }) else { continue }
            emit(Notice(agent: id, kind: .stop, title: agent.label, body: "Có vẻ đã xong việc (CPU đã rảnh)"), now: now)
        }
    }

    /// working → done/idle is a finished turn (timed from when Orca saw it start); → blocked means
    /// the agent waits for the user. The first sighting of an agent only records its state.
    private func observeOrca(agents: [AgentRow], now: Date) {
        anyOrcaWorking = false
        for agent in agents {
            guard let state = agent.orcaState else { continue }
            let id = Self.identity(of: agent)
            let previous = lastOrca[id]
            lastOrca[id] = state
            if state.phase == .working { anyOrcaWorking = true }
            guard let previous, previous != state else { continue }
            switch (previous.phase, state.phase) {
            // From blocked too: the working stretch after the user answered may fall between samples.
            case (.working, .done), (.working, .idle), (.blocked, .done), (.blocked, .idle):
                let duration = state.startedAt.timeIntervalSince(previous.startedAt)
                guard duration >= settings.notifyMinWorkSec else { continue }
                emit(Notice(agent: id, kind: .stop, title: agent.label,
                            body: "Xong việc sau \(Formatters.uptime(seconds: Int(duration)))"), now: now)
            case (_, .blocked) where previous.phase != .blocked:
                emit(Notice(agent: id, kind: .input, title: agent.label, body: "Đang chờ bạn trả lời"), now: now)
            default:
                continue
            }
        }
    }

    /// Faster agent polling while a finish can be imminent: the CPU fallback is timing a working
    /// stretch, or an agent in Orca is working (its Stop lands in Orca's status file).
    var needsFastPolling: Bool { settings.notifyEnabled && (tracker.isTracking || anyOrcaWorking) }

    private func emit(_ notice: Notice, now: Date) {
        guard settings.notifyEnabled else { return }
        let key = "\(notice.agent.pid)-\(notice.agent.startSec)-\(notice.kind.rawValue)"
        if let last = lastPosted[key], now.timeIntervalSince(last) < Self.dedupeWindow { return }
        lastPosted = lastPosted.filter { now.timeIntervalSince($0.value) < Self.dedupeWindow }
        lastPosted[key] = now
        post(notice)
    }

    static func identity(of agent: AgentRow) -> AgentController.Member {
        AgentController.Member(pid: agent.pid, startSec: agent.startSec)
    }
}
