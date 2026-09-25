import Foundation
import Testing
@testable import PortBar

struct AgentEventURLTests {
    @Test func parsesValidEvents() throws {
        let parsed = try #require(AgentEventURL.parse(URL(string: "portbar://agent-event?e=stop&pid=4242")!))
        #expect(parsed.kind == .stop)
        #expect(parsed.pid == 4242)
        #expect(AgentEventURL.parse(URL(string: "portbar://agent-event?pid=7&e=start")!)?.kind == .start)
    }

    @Test func rejectsMalformedEvents() {
        let bad = [
            "http://agent-event?e=stop&pid=42",      // wrong scheme
            "portbar://other?e=stop&pid=42",         // wrong host
            "portbar://agent-event?e=rm&pid=42",     // unknown kind
            "portbar://agent-event?e=stop&pid=1",    // launchd
            "portbar://agent-event?e=stop&pid=-5",
            "portbar://agent-event?e=stop&pid=abc",
            "portbar://agent-event?e=stop",
        ]
        for string in bad { #expect(AgentEventURL.parse(URL(string: string)!) == nil, "\(string)") }
    }

    @Test func hookCommandRoundTrips() throws {
        // What the shell produces after expanding $PPID must parse back.
        let command = AgentEventURL.hookCommand(.input).replacingOccurrences(of: "$PPID", with: "123")
        let url = try #require(command.split(separator: "\"").dropFirst().first.flatMap { URL(string: String($0)) })
        #expect(AgentEventURL.parse(url)?.kind == .input)
    }

    @Test func claudeSnippetIsValidJSONWithThreeHooks() throws {
        let data = Data(AgentEventURL.claudeHooksSnippet.utf8)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["UserPromptSubmit", "Stop", "Notification"])
        #expect(AgentEventURL.claudeHooksSnippet.contains(#"e=start&pid=$PPID"#))
    }

    @Test func codexSnippetIsATomlStringArray() throws {
        let snippet = AgentEventURL.codexNotifySnippet
        #expect(snippet.hasPrefix("notify = ["))
        let array = try #require(
            try JSONSerialization.jsonObject(with: Data(snippet.dropFirst("notify = ".count).utf8)) as? [String])
        #expect(array.first == "/bin/sh")
        #expect(array[2] == AgentEventURL.hookCommand(.stop))
    }
}

struct StatusTransitionTrackerTests {
    private let id = AgentController.Member(pid: 100, startSec: 1)
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func run(_ samples: [(TimeInterval, AgentStatus)]) -> [TimeInterval] {
        var tracker = StatusTransitionTracker()
        var fired: [TimeInterval] = []
        for (offset, status) in samples {
            let done = tracker.update([(id, status)], now: t0 + offset, minWork: 20, idleDebounce: 30)
            if !done.isEmpty { fired.append(offset) }
        }
        return fired
    }

    @Test func sustainedWorkThenIdleFiresOnce() {
        let samples: [(TimeInterval, AgentStatus)] = [(0, .working), (15, .working), (30, .working),
                                                      (33, .idle), (60, .idle), (63, .idle), (90, .idle)]
        #expect(run(samples) == [60])
    }

    @Test func shortPauseInsideLongTaskDoesNotFire() {
        // Waiting on the model drops CPU for a while; the task continues afterwards.
        let samples: [(TimeInterval, AgentStatus)] = [(0, .working), (25, .working), (35, .idle),
                                                      (45, .idle), (50, .working), (53, .idle)]
        #expect(run(samples).isEmpty)
    }

    @Test func shortTaskNeverFires() {
        let samples: [(TimeInterval, AgentStatus)] = [(0, .working), (5, .working), (40, .idle), (80, .idle)]
        #expect(run(samples).isEmpty)
    }

    @Test func pausedOrExcludedAgentsNeverFire() {
        var tracker = StatusTransitionTracker()
        _ = tracker.update([(id, .working)], now: t0, minWork: 20, idleDebounce: 30)
        _ = tracker.update([(id, .working)], now: t0 + 25, minWork: 20, idleDebounce: 30)
        _ = tracker.update([(id, .paused)], now: t0 + 30, minWork: 20, idleDebounce: 30)
        #expect(tracker.update([(id, .idle)], now: t0 + 90, minWork: 20, idleDebounce: 30).isEmpty)
        #expect(!tracker.isTracking)

        _ = tracker.update([(id, .working)], now: t0 + 100, minWork: 20, idleDebounce: 30, excluded: [id])
        #expect(!tracker.isTracking)
    }
}

@MainActor
struct AgentEventCenterTests {
    func makeCenter() throws -> (AgentEventCenter, AppSettings, Box) {
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: "portbar-events-\(UUID())")))
        let center = AgentEventCenter(settings: settings)
        let box = Box()
        center.post = { box.notices.append($0) }
        return (center, settings, box)
    }

    final class Box { var notices: [AgentEventCenter.Notice] = [] }

    func agent(pid: Int32 = 500, status: AgentStatus = .idle) -> AgentRow {
        AgentRow(pid: pid, kind: .claude, cwd: "/tmp/proj", host: "Orca", tty: "ttys001", startSec: 42,
                 status: status, cpuPercent: 0, memoryBytes: 0, childCount: 0)
    }

    let t0 = Date(timeIntervalSince1970: 2_000_000)

    @Test func stopAfterLongTaskNotifiesWithDuration() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.start, agent: agent(), now: t0)
        center.handleHook(.stop, agent: agent(), now: t0 + 125)
        #expect(box.notices.count == 1)
        #expect(box.notices.first?.body == "Xong việc sau 2m")
        #expect(box.notices.first?.title == "Claude Code · proj")
    }

    @Test func stopAfterShortTaskIsSilent() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.start, agent: agent(), now: t0)
        center.handleHook(.stop, agent: agent(), now: t0 + 5)
        #expect(box.notices.isEmpty)
    }

    @Test func stopWithoutStartNotifies() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.stop, agent: agent(), now: t0)
        #expect(box.notices.map(\.body) == ["Xong việc"])
    }

    @Test func inputAlwaysNotifiesButIsDeduplicated() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.input, agent: agent(), now: t0)
        center.handleHook(.input, agent: agent(), now: t0 + 3)
        center.handleHook(.input, agent: agent(), now: t0 + 30)
        #expect(box.notices.count == 2)
    }

    @Test func disabledNotificationsPostNothing() throws {
        let (center, settings, box) = try makeCenter()
        settings.notifyEnabled = false
        center.handleHook(.input, agent: agent(), now: t0)
        #expect(box.notices.isEmpty)
        #expect(center.lastHookEvent != nil)
    }

    @Test func hookedAgentsSkipCPUFallback() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.start, agent: agent(), now: t0)
        center.observe(agents: [agent(status: .working)], now: t0)
        center.observe(agents: [agent(status: .working)], now: t0 + 30)
        center.observe(agents: [agent(status: .idle)], now: t0 + 90)
        #expect(box.notices.isEmpty)
        #expect(!center.needsFastPolling)
    }

    @Test func cpuFallbackNotifiesUnhookedAgent() throws {
        let (center, _, box) = try makeCenter()
        center.observe(agents: [agent(status: .working)], now: t0)
        #expect(center.needsFastPolling)
        center.observe(agents: [agent(status: .working)], now: t0 + 30)
        center.observe(agents: [agent(status: .idle)], now: t0 + 70)
        #expect(box.notices.map(\.body) == ["Có vẻ đã xong việc (CPU đã rảnh)"])
    }

    @Test func unmatchedHookIsRecordedOnly() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.stop, agent: nil, now: t0)
        #expect(box.notices.isEmpty)
        #expect(center.lastHookEvent?.contains("không khớp") == true)
    }
}

extension AgentEventCenterTests {
    @Test func silentHooksHandBackToCPUFallback() throws {
        let (center, _, box) = try makeCenter()
        // One hook event, then hooks go quiet (config overwritten): after the silence limit the
        // CPU fallback watches the agent again.
        center.handleHook(.input, agent: agent(), now: t0)
        box.notices.removeAll()
        let later = t0 + AgentEventCenter.hookSilenceLimit + 1
        center.observe(agents: [agent(status: .working)], now: later)
        center.observe(agents: [agent(status: .working)], now: later + 30)
        center.observe(agents: [agent(status: .idle)], now: later + 70)
        #expect(box.notices.count == 1)
    }

    @Test func openHookedTaskStaysExcludedPastSilenceLimit() throws {
        let (center, _, box) = try makeCenter()
        center.handleHook(.start, agent: agent(), now: t0)
        let later = t0 + AgentEventCenter.hookSilenceLimit + 1
        center.observe(agents: [agent(status: .working)], now: later)
        center.observe(agents: [agent(status: .working)], now: later + 30)
        center.observe(agents: [agent(status: .idle)], now: later + 70)
        #expect(box.notices.isEmpty)
    }
}

struct NotifierUserInfoTests {
    @Test func agentSurvivesNotificationRoundTrip() throws {
        let member = AgentController.Member(pid: 4321, startSec: 1_790_000_000)
        // UserNotifications stores userInfo as a property list: values come back as NSNumber.
        let data = try PropertyListSerialization.data(
            fromPropertyList: Notifier.userInfo(for: member), format: .binary, options: 0)
        let restored = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any])
        #expect(Notifier.agent(from: restored) == member)
        #expect(Notifier.agent(from: ["pid": "x"]) == nil)
    }
}
