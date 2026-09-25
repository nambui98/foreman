import Darwin
import Foundation

/// Delivers SIGTERM/SIGKILL to a process or its whole process group and waits for it to exit.
/// Never escalates privileges: EPERM is reported, not worked around.
struct ProcessKiller: Sendable {
    var gracePeriod: Duration = .seconds(3)
    var pollInterval: Duration = .milliseconds(200)

    /// Sends SIGTERM and waits up to `gracePeriod`; `.stillRunning` means the caller may force-kill.
    func terminate(pid: Int32, wholeGroup: Bool) async -> KillOutcome {
        await send(SIGTERM, pid: pid, wholeGroup: wholeGroup, wait: gracePeriod)
    }

    func forceKill(pid: Int32, wholeGroup: Bool) async -> KillOutcome {
        await send(SIGKILL, pid: pid, wholeGroup: wholeGroup, wait: .seconds(1))
    }

    private func send(_ signal: Int32, pid: Int32, wholeGroup: Bool, wait: Duration) async -> KillOutcome {
        if let reason = refusal(pid: pid, wholeGroup: wholeGroup) { return .refused(reason) }

        let result: Int32
        if wholeGroup, let pgid = ProcessInspector.bsdInfo(pid: pid).map({ Int32($0.pbi_pgid) }) {
            result = killpg(pgid, signal)
        } else {
            result = kill(pid, signal)
        }
        if result != 0 {
            switch errno {
            case EPERM: return .notPermitted
            case ESRCH: return .notFound
            default: return .refused(String(cString: strerror(errno)))
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now + wait
        while clock.now < deadline {
            if !ProcessInspector.isAlive(pid: pid) { return .exited }
            try? await Task.sleep(for: pollInterval)
        }
        return ProcessInspector.isAlive(pid: pid) ? .stillRunning : .exited
    }

    /// Safety guards: never signal ourselves, launchd/kernel, or a group that contains us.
    private func refusal(pid: Int32, wholeGroup: Bool) -> String? {
        if pid <= 1 { return String(localized: "Can't stop a system process (PID \(Int(pid)))") }
        if pid == getpid() { return String(localized: "Foreman can't stop itself from the list") }
        if wholeGroup, case .failure(let reason) = Self.groupMembers(of: pid) { return reason.message }
        return nil
    }

    struct GroupRefusal: Error { let message: String }

    /// Members of `pid`'s process group as `name (PID)`, or why a group kill is unsafe.
    ///
    /// Processes launched by non-interactive wrappers (make, IDE tasks, `sh script.sh`) can share
    /// the process group of an interactive terminal shell; signalling that group would close the
    /// user's terminal session, so any group containing a session leader with a controlling
    /// terminal is refused.
    static func groupMembers(of pid: Int32) -> Result<[String], GroupRefusal> {
        guard let pgid = ProcessInspector.bsdInfo(pid: pid).map({ Int32($0.pbi_pgid) }) else {
            return .failure(GroupRefusal(message: String(localized: "Can't read the process group")))
        }
        if pgid <= 1 || pgid == getpgrp() {
            return .failure(GroupRefusal(message: String(localized: "Process group \(Int(pgid)) is not safe to stop")))
        }
        var members: [String] = []
        for member in ProcessInspector.groupMembers(pgid: pgid) {
            guard let info = ProcessInspector.bsdInfo(pid: member) else { continue }
            let name = ProcessInspector.name(of: info)
            let flags = Int32(bitPattern: info.pbi_flags)
            if flags & PROC_FLAG_SLEADER != 0 && flags & PROC_FLAG_CONTROLT != 0 {
                return .failure(GroupRefusal(
                    message: String(localized: "The group contains a terminal shell (\(name), PID \(Int(member))) — stop processes one by one")))
            }
            members.append("\(name) (\(member))")
        }
        return .success(members)
    }
}
