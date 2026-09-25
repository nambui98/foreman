import Foundation

/// Infers "task finished" from CPU status for agents that send no hook events.
///
/// Tree CPU drops while an agent waits for the model, so a single idle sample means nothing: a
/// working stretch only ends after `idleDebounce` seconds without a working sample, and it only
/// counts as a task when it lasted at least `minWork` seconds.
struct StatusTransitionTracker {
    private struct Stretch {
        let start: Date
        var lastWorking: Date
    }

    private var stretches: [AgentController.Member: Stretch] = [:]

    /// Returns the agents whose task just finished.
    mutating func update(
        _ agents: [(id: AgentController.Member, status: AgentStatus)],
        now: Date, minWork: TimeInterval, idleDebounce: TimeInterval,
        excluded: Set<AgentController.Member> = []
    ) -> [AgentController.Member] {
        var finished: [AgentController.Member] = []
        var seen: Set<AgentController.Member> = []
        for (id, status) in agents {
            seen.insert(id)
            if excluded.contains(id) {
                stretches[id] = nil
                continue
            }
            switch status {
            case .working:
                stretches[id, default: Stretch(start: now, lastWorking: now)].lastWorking = now
            case .paused, .waiting:
                stretches[id] = nil
            case .idle:
                guard let stretch = stretches[id], now.timeIntervalSince(stretch.lastWorking) >= idleDebounce else {
                    continue
                }
                if stretch.lastWorking.timeIntervalSince(stretch.start) >= minWork { finished.append(id) }
                stretches[id] = nil
            }
        }
        stretches = stretches.filter { seen.contains($0.key) }
        return finished
    }

    /// True while some agent is inside a working stretch (the monitor polls agents faster then).
    var isTracking: Bool { !stretches.isEmpty }
}
