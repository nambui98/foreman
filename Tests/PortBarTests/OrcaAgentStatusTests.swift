import Foundation
import Testing
@testable import PortBar

struct OrcaStatusReaderTests {
    static let sample = """
    {"version": 1, "authorityCommitments": {}, "entries": {
      "tab1:leaf1": {"paneKey": "tab1:leaf1", "hookEventName": "PreToolUse",
                     "payload": {"state": "working", "prompt": "secret prompt", "agentType": "claude"},
                     "receivedAt": 1790312100000, "stateStartedAt": 1790312000000},
      "tab2:leaf2": {"payload": {"state": "blocked"}, "receivedAt": 1790312100000, "stateStartedAt": 1790312090000},
      "tab3:leaf3": {"payload": {"state": "done"}, "stateStartedAt": 1790312050000},
      "tab4:leaf4": {"payload": {"state": "something-new"}, "stateStartedAt": 1790312050000},
      "tab5:leaf5": {"payload": {}, "stateStartedAt": 1790312050000}
    }}
    """

    @Test func parsesKnownStatesOnly() throws {
        let states = OrcaStatusReader.parse(Data(Self.sample.utf8))
        #expect(Set(states.keys) == ["tab1:leaf1", "tab2:leaf2", "tab3:leaf3"])
        let working = try #require(states["tab1:leaf1"])
        #expect(working.phase == .working)
        #expect(working.startedAt == Date(timeIntervalSince1970: 1_790_312_000))
        #expect(working.lastEventAt == Date(timeIntervalSince1970: 1_790_312_100))
        #expect(states["tab2:leaf2"]?.phase == .blocked)
        // No receivedAt: the state start is the last known event.
        #expect(states["tab3:leaf3"]?.lastEventAt == Date(timeIntervalSince1970: 1_790_312_050))
        #expect(OrcaStatusReader.parse(Data("not json".utf8)).isEmpty)
    }

    @Test func rereadsOnlyWhenTheFileChanges() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "orca-status-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var reader = OrcaStatusReader(url: url)
        #expect(reader.states().isEmpty)  // missing file

        try Data(Self.sample.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: url.path)
        #expect(reader.states().count == 3)

        // Same modification date → cached result even though the bytes differ.
        try Data(#"{"entries": {}}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: url.path)
        #expect(reader.states().count == 3)

        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: url.path)
        #expect(reader.states().isEmpty)
    }
}

struct AgentStatusResolutionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func orca(_ phase: OrcaAgentState.Phase, lastEventAgo: TimeInterval = 5) -> OrcaAgentState {
        OrcaAgentState(phase: phase, startedAt: now - 300, lastEventAt: now - lastEventAgo)
    }

    @Test func orcaStateWinsOverCPU() {
        // Waiting on the model: CPU ~0 but Orca says working.
        #expect(AgentRowBuilder.status(paused: false, orca: orca(.working), cpuPercent: 0.4, now: now) == .working)
        // Turn over, but a dev server in the tree keeps CPU up.
        #expect(AgentRowBuilder.status(paused: false, orca: orca(.done), cpuPercent: 80, now: now) == .idle)
        #expect(AgentRowBuilder.status(paused: false, orca: orca(.idle), cpuPercent: 0, now: now) == .idle)
        #expect(AgentRowBuilder.status(paused: false, orca: orca(.blocked), cpuPercent: 0, now: now) == .waiting)
        #expect(AgentRowBuilder.status(paused: true, orca: orca(.working), cpuPercent: 50, now: now) == .paused)
    }

    @Test func staleWorkingIsIdleUnlessTreeIsBusy() {
        let stale = orca(.working, lastEventAgo: AgentRowBuilder.orcaStaleAfter + 1)
        #expect(AgentRowBuilder.status(paused: false, orca: stale, cpuPercent: 1, now: now) == .idle)
        // A long tool run (build, tests) keeps the tree busy without new hook events.
        #expect(AgentRowBuilder.status(paused: false, orca: stale, cpuPercent: 60, now: now) == .working)
    }

    @Test func withoutOrcaFallsBackToCPU() {
        #expect(AgentRowBuilder.status(paused: false, orca: nil, cpuPercent: 25, now: now) == .working)
        #expect(AgentRowBuilder.status(paused: false, orca: nil, cpuPercent: 2, now: now) == .idle)
    }

    @Test func rowsJoinOrcaStateByPaneKey() {
        var inOrca = AgentProcess(pid: 1, kind: .claude, startSec: 0, tty: "ttys001", host: "Orca")
        inOrca.orcaPaneKey = "tab:leaf"
        let elsewhere = AgentProcess(pid: 2, kind: .codex, startSec: 0, tty: nil, host: "Codex")
        let rows = AgentRowBuilder.rows(
            agents: [inOrca, elsewhere], usage: [:], cpuPercent: [1: 0, 2: 0], paused: [],
            orca: ["tab:leaf": orca(.blocked)], now: now)
        #expect(rows.map(\.status) == [.waiting, .idle])  // waiting sorts first
        #expect(rows.first?.orcaState?.phase == .blocked)
        #expect(rows.last?.orcaState == nil)
    }
}

@MainActor
struct OrcaNotificationTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func setup() throws -> (AgentEventCenter, AgentEventCenterTests.Box) {
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: "portbar-orca-\(UUID())")))
        let center = AgentEventCenter(settings: settings)
        let box = AgentEventCenterTests.Box()
        center.post = { box.notices.append($0) }
        return (center, box)
    }

    private func agent(_ phase: OrcaAgentState.Phase, since: Date, cpu status: AgentStatus = .idle) -> AgentRow {
        var row = AgentRow(pid: 700, kind: .claude, cwd: "/tmp/app", host: "Orca", tty: "ttys002", startSec: 9,
                           status: status, cpuPercent: 0, memoryBytes: 0, childCount: 0)
        row.orcaState = OrcaAgentState(phase: phase, startedAt: since, lastEventAt: since)
        return row
    }

    @Test func finishedTurnNotifiesWithDuration() throws {
        let (center, box) = try setup()
        center.observe(agents: [agent(.working, since: t0)], now: t0)
        #expect(center.needsFastPolling)
        center.observe(agents: [agent(.done, since: t0 + 95)], now: t0 + 97)
        #expect(box.notices.map(\.body) == ["Xong việc sau 1m"])
    }

    @Test func shortTurnIsSilent() throws {
        let (center, box) = try setup()
        center.observe(agents: [agent(.working, since: t0)], now: t0)
        center.observe(agents: [agent(.done, since: t0 + 5)], now: t0 + 6)
        #expect(box.notices.isEmpty)
    }

    @Test func blockedNotifiesOnce() throws {
        let (center, box) = try setup()
        center.observe(agents: [agent(.working, since: t0)], now: t0)
        center.observe(agents: [agent(.blocked, since: t0 + 40)], now: t0 + 41)
        center.observe(agents: [agent(.blocked, since: t0 + 40)], now: t0 + 60)
        #expect(box.notices.map(\.body) == ["Đang chờ bạn trả lời"])
    }

    @Test func firstSightingOnlyRecords() throws {
        let (center, box) = try setup()
        center.observe(agents: [agent(.done, since: t0)], now: t0 + 500)
        #expect(box.notices.isEmpty)
        #expect(!center.needsFastPolling)
    }

    @Test func orcaAgentsSkipCPUFallback() throws {
        let (center, box) = try setup()
        center.observe(agents: [agent(.working, since: t0, cpu: .working)], now: t0)
        center.observe(agents: [agent(.working, since: t0, cpu: .working)], now: t0 + 30)
        // CPU says idle for a long time but Orca still says working (model wait): no guess.
        center.observe(agents: [agent(.working, since: t0, cpu: .idle)], now: t0 + 90)
        #expect(box.notices.isEmpty)
    }
}
