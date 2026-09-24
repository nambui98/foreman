import Darwin
import Foundation
import Testing
@testable import PortBar

@Suite(.serialized)
struct ProcessKillerTests {
    private func spawn(_ script: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        return process
    }

    @Test func sigtermStopsCooperativeProcess() async throws {
        let child = try spawn("exec sleep 60")
        let outcome = await ProcessKiller().terminate(pid: child.processIdentifier, wholeGroup: false)
        #expect(outcome == .exited)
    }

    @Test func processIgnoringSigtermNeedsForce() async throws {
        let child = try spawn("trap '' TERM; while :; do sleep 0.1; done")
        try await Task.sleep(for: .milliseconds(200))  // let the trap install
        let killer = ProcessKiller(gracePeriod: .milliseconds(600))
        #expect(await killer.terminate(pid: child.processIdentifier, wholeGroup: false) == .stillRunning)
        #expect(await killer.forceKill(pid: child.processIdentifier, wholeGroup: false) == .exited)
    }

    @Test func refusesUnsafeTargets() async {
        let killer = ProcessKiller()
        #expect(await killer.terminate(pid: 1, wholeGroup: false) != .exited)
        #expect(await killer.terminate(pid: 0, wholeGroup: false) != .exited)
        guard case .refused = await killer.terminate(pid: getpid(), wholeGroup: false) else {
            Issue.record("must refuse to kill itself"); return
        }
        guard case .refused = await killer.terminate(pid: getpid(), wholeGroup: true) else {
            Issue.record("must refuse to kill own group"); return
        }
    }

    @Test func groupKillStopsChildTreeButNotUs() async throws {
        // Foundation's Process puts the child in its own process group; sh + its sleep share it.
        let child = try spawn("sleep 60 & wait")
        try await Task.sleep(for: .milliseconds(200))
        let pgid = try #require(ProcessInspector.bsdInfo(pid: child.processIdentifier)).pbi_pgid
        #expect(Int32(pgid) != getpgrp())
        #expect(await ProcessKiller().terminate(pid: child.processIdentifier, wholeGroup: true) == .exited)
        try await Task.sleep(for: .milliseconds(200))
        #expect(killpg(Int32(pgid), 0) != 0)  // background sleep is gone too
        #expect(ProcessInspector.isAlive(pid: getpid()))
    }

    @Test func groupSharedWithTerminalShellIsRefused() async throws {
        // `script` gives the shell a pseudo-terminal: it becomes a session leader with a controlling
        // terminal, and its background `sleep` inherits the shell's process group (no job control) —
        // the same shape as a dev server launched by a wrapper script inside a terminal.
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("portbar-\(UUID()).pid")
        let host = try spawn("script -q /dev/null /bin/sh -c 'sleep 60 & echo $! > \(pidFile.path); wait'")
        defer { host.terminate() }
        var sleeper: Int32?
        for _ in 0..<50 where sleeper == nil {
            try await Task.sleep(for: .milliseconds(100))
            sleeper = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        let pid = try #require(sleeper)
        defer { kill(pid, SIGKILL) }

        guard case .failure(let refusal) = ProcessKiller.groupMembers(of: pid) else {
            Issue.record("group containing a terminal shell must be refused"); return
        }
        #expect(refusal.message.contains("terminal"))
        guard case .refused = await ProcessKiller().terminate(pid: pid, wholeGroup: true) else {
            Issue.record("terminate(wholeGroup:) must refuse too"); return
        }
        #expect(ProcessInspector.isAlive(pid: pid))
        // Killing just that one process is still allowed.
        #expect(await ProcessKiller().terminate(pid: pid, wholeGroup: false) == .exited)
    }

    @Test func groupMembersListsWholeTree() async throws {
        let child = try spawn("sleep 60 & wait")
        try await Task.sleep(for: .milliseconds(200))
        let members = try ProcessKiller.groupMembers(of: child.processIdentifier).get()
        #expect(members.count == 2)
        #expect(members.contains { $0.hasPrefix("sleep (") })
        _ = await ProcessKiller().forceKill(pid: child.processIdentifier, wholeGroup: true)
    }

    @Test func missingPidIsNotFound() async {
        #expect(await ProcessKiller().terminate(pid: 999_999, wholeGroup: false) == .notFound)
    }
}
