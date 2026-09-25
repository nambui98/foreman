import Foundation
import Testing
@testable import Foreman

struct UsageTrackerTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!

    private func claudeLine(id: String, request: String, session: String, time: String, model: String = "claude-sonnet-5",
                            input: Int = 10, output: Int = 100, cacheRead: Int = 1_000, cacheWrite: Int = 0) -> String {
        #"{"parentUuid":"x","sessionId":"\#(session)","requestId":"\#(request)","timestamp":"\#(time)","message":{"id":"\#(id)","model":"\#(model)","content":[{"type":"text","text":"a \"usage\":{\"input_tokens\":999} decoy"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"cache_creation":{"ephemeral_5m_input_tokens":\#(cacheWrite),"ephemeral_1h_input_tokens":0}}},"type":"assistant"}"#
    }

    private func makeRoots() throws -> (URL, URL) {
        let base = FileManager.default.temporaryDirectory.appending(path: "foreman-usage-\(UUID())")
        let claude = base.appending(path: "claude/-Users-me-app")
        let codex = base.appending(path: "codex/2026/09/25")
        try FileManager.default.createDirectory(at: claude.appending(path: "s1/subagents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        return (base.appending(path: "claude"), base.appending(path: "codex"))
    }

    @Test func countsTodayOnceAndPricesIt() throws {
        let (claudeRoot, codexRoot) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: claudeRoot.deletingLastPathComponent()) }
        let main = claudeRoot.appending(path: "-Users-me-app/s1.jsonl")
        let lines = [
            claudeLine(id: "msg_1", request: "req_1", session: "s1", time: "2026-09-25T08:00:00.000Z"),
            claudeLine(id: "msg_1", request: "req_1", session: "s1", time: "2026-09-25T08:00:01.000Z"),  // same message, next block
            claudeLine(id: "msg_0", request: "req_0", session: "s1", time: "2026-09-24T23:59:59.000Z"),  // yesterday
            #"{"type":"user","timestamp":"2026-09-25T08:00:02.000Z","message":{"content":"hi"}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: main, atomically: true, encoding: .utf8)
        let sub = claudeRoot.appending(path: "-Users-me-app/s1/subagents/agent-a.jsonl")
        try (claudeLine(id: "msg_2", request: "req_2", session: "s1", time: "2026-09-25T09:00:00.000Z",
                        model: "claude-opus-5", input: 20, output: 200, cacheRead: 0, cacheWrite: 400) + "\n")
            .write(to: sub, atomically: true, encoding: .utf8)

        var tracker = UsageTracker(claudeRoot: claudeRoot, codexRoot: codexRoot)
        let snapshot = tracker.update(now: now, calendar: calendar)
        let s1 = try #require(snapshot.claudeBySession["s1"])
        #expect(s1.input == 30)
        #expect(s1.output == 300)
        #expect(s1.cacheRead == 1_000)
        #expect(s1.cacheWrite == 400)
        // sonnet-5: 10×2 + 100×10 + 1000×0.2 = 1220 ; opus-5: 20×5 + 200×25 + 400×5×1.25 = 7600 (per 1M)
        #expect(abs(s1.cost - 8_820 / 1_000_000) < 1e-9)
        #expect(snapshot.claudeTotal == s1)
    }

    @Test func readsOnlyAppendedCompleteLines() throws {
        let (claudeRoot, codexRoot) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: claudeRoot.deletingLastPathComponent()) }
        let file = claudeRoot.appending(path: "-Users-me-app/s2.jsonl")
        let first = claudeLine(id: "msg_a", request: "r", session: "s2", time: "2026-09-25T08:00:00Z")
        let second = claudeLine(id: "msg_b", request: "r", session: "s2", time: "2026-09-25T08:05:00Z")
        try (first + "\n" + second.prefix(40)).write(to: file, atomically: true, encoding: .utf8)  // second still being written
        var tracker = UsageTracker(claudeRoot: claudeRoot, codexRoot: codexRoot)
        #expect(tracker.update(now: now, calendar: calendar).claudeTotal.output == 100)
        try (first + "\n" + second + "\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(tracker.update(now: now, calendar: calendar).claudeTotal.output == 200)
        #expect(tracker.update(now: now, calendar: calendar).claudeTotal.output == 200)  // nothing new
    }

    @Test func codexTokensSinceMidnightAndLimits() throws {
        let (claudeRoot, codexRoot) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: claudeRoot.deletingLastPathComponent()) }
        func event(_ time: String, total: Int, used: Double) -> String {
            #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(total)}},"rate_limits":{"primary":{"used_percent":\#(used),"window_minutes":300,"resets_at":1790338644},"secondary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1790436951}}}}"#
        }
        let file = codexRoot.appending(path: "2026/09/25/rollout.jsonl")
        try [event("2026-09-24T23:00:00.000Z", total: 5_000, used: 3),
             event("2026-09-25T01:00:00.000Z", total: 7_500, used: 9),
             event("2026-09-25T02:00:00.000Z", total: 9_000, used: 12)].joined(separator: "\n").appending("\n")
            .write(to: file, atomically: true, encoding: .utf8)
        var tracker = UsageTracker(claudeRoot: claudeRoot, codexRoot: codexRoot)
        let snapshot = tracker.update(now: now, calendar: calendar)
        #expect(snapshot.codexTokens == 4_000)
        #expect(snapshot.codexLimits?.primary?.usedPercent == 12)
        #expect(snapshot.codexLimits?.secondary?.windowMinutes == 10_080)
    }

    @Test func dayStartsAtLocalMidnight() throws {
        let (claudeRoot, codexRoot) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: claudeRoot.deletingLastPathComponent()) }
        var saigon = Calendar(identifier: .gregorian)
        saigon.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!  // UTC+7: local midnight = 17:00Z
        let file = claudeRoot.appending(path: "-Users-me-app/s3.jsonl")
        try [claudeLine(id: "msg_before", request: "r", session: "s3", time: "2026-09-24T16:59:59.000Z", output: 1),
             claudeLine(id: "msg_after", request: "r", session: "s3", time: "2026-09-24T17:00:00.000Z", output: 2)]
            .joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        var tracker = UsageTracker(claudeRoot: claudeRoot, codexRoot: codexRoot)
        let localMorning = ISO8601DateFormatter().date(from: "2026-09-24T20:00:00Z")!  // 03:00 on the 25th in Saigon
        #expect(tracker.update(now: localMorning, calendar: saigon).claudeTotal.output == 2)
    }

    @Test func pricingAndFormatting() {
        #expect(ModelPricing.price(for: "claude-haiku-4-5-20251001")?.input == 1)
        #expect(ModelPricing.price(for: "claude-opus-5-5")?.cacheRead == 0.20)
        #expect(ModelPricing.price(for: "claude-opus-5")?.output == 25)
        #expect(ModelPricing.price(for: "<synthetic>") == nil)
        #expect(ModelPricing.cost(model: "<synthetic>", input: 1_000_000, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0) == 0)
        #expect(Formatters.tokens(845) == "845")
        #expect(Formatters.tokens(12_300) == "12K")
        #expect(Formatters.tokens(3_400_000) == "3.4M")
        #expect(Formatters.tokens(1_306_746_900) == "1.31B")
        #expect(Formatters.dollars(0.842) == "$0.84")
        #expect(Formatters.dollars(408.53) == "$409")
    }
}
