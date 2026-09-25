import Darwin
import Foundation

/// Pauses, resumes and stops agents' process trees.
///
/// Pause never signals the agent process itself: SIGSTOP on a terminal's foreground job makes the
/// shell take the terminal back, and after SIGCONT the job reads the tty from the background and
/// dies. Only descendants (tool shells, MCP servers, dev servers, builds) are stopped — they run in
/// their own process groups, so the terminal is untouched.
@MainActor
final class AgentController {
    /// A process identity that survives PID reuse.
    struct Member: Hashable, Sendable {
        let pid: Int32
        let startSec: UInt64
    }

    private(set) var paused: [Int32: Set<Member>] = [:]
    private let currentUID = getuid()
    private let defaults: UserDefaults?
    var gracePeriod: Duration = .seconds(3)

    static let defaultsKey = "pausedMembers"

    /// `defaults` persists paused members so a crash or Force Quit (which skip
    /// applicationWillTerminate) cannot leave processes frozen: the next launch continues them.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        resumeOrphans()
    }

    /// Continues processes a previous PortBar instance paused and never released.
    private func resumeOrphans() {
        guard let saved = defaults?.array(forKey: Self.defaultsKey) as? [[String: UInt64]] else { return }
        for item in saved {
            guard let pid = item["pid"].map({ Int32(truncatingIfNeeded: $0) }), let start = item["start"] else { continue }
            let member = Member(pid: pid, startSec: start)
            if isSameProcess(member) { kill(pid, SIGCONT) }
        }
        defaults?.removeObject(forKey: Self.defaultsKey)
    }

    private func persist() {
        guard let defaults else { return }
        let members = paused.values.flatMap { $0 }.map { ["pid": UInt64($0.pid), "start": $0.startSec] }
        if members.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(members, forKey: Self.defaultsKey)
        }
    }

    func isPaused(_ agentPid: Int32) -> Bool { paused[agentPid] != nil }

    func pause(agentPid: Int32, table: ProcessTable) {
        var members = paused[agentPid] ?? []
        for member in signalTargets(agentPid: agentPid, table: table, includeAgent: false)
        where isSameProcess(member) && kill(member.pid, SIGSTOP) == 0 {
            members.insert(member)
        }
        paused[agentPid] = members
        persist()
    }

    func resume(agentPid: Int32) {
        for member in paused.removeValue(forKey: agentPid) ?? [] where isSameProcess(member) {
            kill(member.pid, SIGCONT)
        }
        persist()
    }

    /// Called every refresh: pauses descendants spawned since `pause`, and releases members of
    /// agents that are gone so nothing stays frozen.
    func reconcile(table: ProcessTable, livePids: Set<Int32>) {
        for agentPid in paused.keys {
            if livePids.contains(agentPid) {
                pause(agentPid: agentPid, table: table)  // also persists
            } else {
                resume(agentPid: agentPid)
            }
        }
    }

    func resumeAll() {
        for agentPid in paused.keys { resume(agentPid: agentPid) }
    }

    /// Everything a stop will signal, agent first, as `(member, name)`.
    func stopTargets(agentPid: Int32, table: ProcessTable) -> [(Member, String)] {
        signalTargets(agentPid: agentPid, table: table, includeAgent: true)
            .map { ($0, table.entries[$0.pid]?.name ?? "?") }
    }

    /// SIGTERM (or SIGKILL) the agent and its whole tree, then wait for all of them to exit.
    func stop(agentPid: Int32, table: ProcessTable, force: Bool) async -> KillOutcome {
        let targets = signalTargets(agentPid: agentPid, table: table, includeAgent: true)
        guard !targets.isEmpty else { return .notFound }
        let signal = force ? SIGKILL : SIGTERM
        for member in targets where isSameProcess(member) {
            kill(member.pid, signal)
        }
        // A stopped process only acts on SIGTERM once continued.
        for member in paused.removeValue(forKey: agentPid) ?? [] where isSameProcess(member) {
            kill(member.pid, SIGCONT)
        }
        persist()

        let clock = ContinuousClock()
        let deadline = clock.now + (force ? .seconds(1) : gracePeriod)
        while clock.now < deadline {
            if !targets.contains(where: isRunning) { return .exited }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return targets.contains(where: isRunning) ? .stillRunning : .exited
    }

    /// Agent (optionally) plus descendants, minus anything unsafe: PortBar itself and its
    /// ancestors, launchd/kernel, and other users' processes.
    private func signalTargets(agentPid: Int32, table: ProcessTable, includeAgent: Bool) -> [Member] {
        let selfPid = getpid()
        let protected = Set(table.ancestors(of: selfPid) + [selfPid])
        let pids = (includeAgent ? [agentPid] : []) + table.descendants(of: agentPid)
        return pids.compactMap { pid in
            guard pid > 1, !protected.contains(pid),
                  let entry = table.entries[pid], entry.uid == currentUID else { return nil }
            return Member(pid: pid, startSec: entry.startSec)
        }
    }

    /// Libproc only (no sysctl fallback like ProcessTable): every target is filtered to the
    /// current user by `signalTargets`, and libproc can read all of our own processes.
    private func isSameProcess(_ member: Member) -> Bool {
        ProcessInspector.bsdInfo(pid: member.pid)?.pbi_start_tvsec == member.startSec
    }

    private func isRunning(_ member: Member) -> Bool {
        isSameProcess(member) && ProcessInspector.isAlive(pid: member.pid)
    }
}
