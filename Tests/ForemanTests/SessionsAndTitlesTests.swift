import Foundation
import Testing
@testable import Foreman

struct ClaudeSessionReaderTests {
    @Test func parsesSessionFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "foreman-sessions-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"pid": 4242, "sessionId": "abc-123", "cwd": "/tmp/app", "status": "busy", "name": "app-1f"}"#.utf8)
            .write(to: dir.appending(path: "4242.json"))
        try Data(#"{"pid": 77, "sessionId": "def", "status": "compacting"}"#.utf8).write(to: dir.appending(path: "77.json"))
        try Data("garbage".utf8).write(to: dir.appending(path: "1.json"))
        try Data("ignored".utf8).write(to: dir.appending(path: "4242.key"))

        var reader = ClaudeSessionReader(directory: dir)
        let sessions = reader.sessions()
        #expect(Set(sessions.keys) == [4242, 77])
        #expect(sessions[4242] == ClaudeSession(pid: 4242, sessionId: "abc-123", status: .busy, cwd: "/tmp/app"))
        #expect(sessions[77]?.status == nil)  // unknown status: fall back to other sources
        #expect(reader.sessions().count == 2)  // cached pass
    }

    @Test func claudeStatusRanksBetweenOrcaAndCPU() {
        let now = Date()
        #expect(AgentRowBuilder.status(paused: false, orca: nil, claude: .busy, cpuPercent: 0, now: now) == .working)
        #expect(AgentRowBuilder.status(paused: false, orca: nil, claude: .shell, cpuPercent: 0, now: now) == .working)
        #expect(AgentRowBuilder.status(paused: false, orca: nil, claude: .idle, cpuPercent: 90, now: now) == .idle)
        let blocked = OrcaAgentState(phase: .blocked, startedAt: now, lastEventAt: now)
        #expect(AgentRowBuilder.status(paused: false, orca: blocked, claude: .busy, cpuPercent: 0, now: now) == .waiting)
    }

    @Test func rowsCarrySessionAndSource() {
        let claude = AgentProcess(pid: 9, kind: .claude, startSec: 0, tty: nil, host: "Terminal")
        let codex = AgentProcess(pid: 10, kind: .codex, startSec: 0, tty: nil, host: "Terminal")
        let session = ClaudeSession(pid: 9, sessionId: "s-1", status: .busy, cwd: nil)
        let rows = AgentRowBuilder.rows(
            agents: [claude, codex], usage: [:], cpuPercent: [:], paused: [],
            claude: [9: session, 10: ClaudeSession(pid: 10, sessionId: "x", status: .busy, cwd: nil)])
        let claudeRow = rows.first { $0.pid == 9 }
        #expect(claudeRow?.statusSource == .claude)
        #expect(claudeRow?.claudeSessionId == "s-1")
        // A session file is only trusted for Claude agents.
        #expect(rows.first { $0.pid == 10 }?.statusSource == .cpu)
    }
}

struct OrcaTerminalTitlesTests {
    @Test func cleansTitles() {
        #expect(OrcaTerminalTitles.clean("✳ Fix login redirect") == "Fix login redirect")
        #expect(OrcaTerminalTitles.clean("◑ Làm hết giúp tôi") == "Làm hết giúp tôi")
        #expect(OrcaTerminalTitles.clean("⠂ Deploy") == "Deploy")
        #expect(OrcaTerminalTitles.clean("✳ Claude Code") == nil)
        #expect(OrcaTerminalTitles.clean("..ct/landingpro") == nil)
        #expect(OrcaTerminalTitles.clean("✳ ") == nil)
    }

    @Test func parsesTerminalList() {
        let json = #"{"ok": true, "result": {"terminals": [{"handle": "term_1", "title": "◐ Design mới"}, {"handle": "term_2", "title": "Claude Code"}, {"handle": "term_3"}]}}"#
        #expect(OrcaTerminalTitles.parse(Data(json.utf8)) == ["term_1": "Design mới"])
        #expect(OrcaTerminalTitles.parse(Data("x".utf8)).isEmpty)
    }
}

@MainActor
struct KeepAwakeTests {
    @Test func assertionFollowsActivity() {
        let keepAwake = KeepAwake()
        keepAwake.update(active: true)
        #expect(keepAwake.isActive)
        keepAwake.update(active: true)  // idempotent
        keepAwake.update(active: false)
        #expect(!keepAwake.isActive)
    }
}
