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
    /// Agents that reported through hooks: their CPU status is no longer used to guess.
    @ObservationIgnored private var hooked: Set<AgentController.Member> = []
    @ObservationIgnored private var lastPosted: [String: Date] = [:]
    @ObservationIgnored private var tracker = StatusTransitionTracker()

    /// The same notice for the same agent is dropped inside this window (hooks can fire in bursts).
    static let dedupeWindow: TimeInterval = 10

    init(settings: AppSettings) {
        self.settings = settings
    }

    func handleHook(_ kind: AgentEventKind, agent: AgentRow?, now: Date = Date()) {
        lastHookEvent = "\(now.formatted(date: .omitted, time: .standard)) · \(kind.rawValue) · "
            + (agent?.label ?? "không khớp agent nào")
        guard let agent else { return }
        let id = Self.identity(of: agent)
        hooked.insert(id)
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

    /// CPU fallback for agents without hooks; call after every agent refresh.
    func observe(agents: [AgentRow], now: Date = Date()) {
        let finished = tracker.update(
            agents.map { (Self.identity(of: $0), $0.status) }, now: now,
            minWork: settings.notifyMinWorkSec, idleDebounce: settings.cpuIdleDebounceSec, excluded: hooked)
        let live = Set(agents.map(Self.identity(of:)))
        hooked.formIntersection(live)
        taskStart = taskStart.filter { live.contains($0.key) }
        for id in finished {
            guard let agent = agents.first(where: { Self.identity(of: $0) == id }) else { continue }
            emit(Notice(agent: id, kind: .stop, title: agent.label, body: "Có vẻ đã xong việc (CPU đã rảnh)"), now: now)
        }
    }

    /// Faster agent polling is only needed while the CPU fallback is timing a working stretch.
    var needsFastPolling: Bool { settings.notifyEnabled && tracker.isTracking }

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
