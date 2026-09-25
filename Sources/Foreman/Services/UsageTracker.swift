import Foundation

/// Token counts for one day, with an API-list-price cost estimate when every model is known.
struct TokenUsage: Sendable, Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    /// USD at API list prices; Claude subscriptions are not billed per token.
    var cost: Double = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, output: lhs.output + rhs.output, cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
             cacheRead: lhs.cacheRead + rhs.cacheRead, cost: lhs.cost + rhs.cost)
    }
}

/// Codex plan usage as reported in its session logs.
struct CodexLimits: Sendable, Equatable {
    struct Window: Sendable, Equatable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Date?
    }

    let primary: Window?
    let secondary: Window?
}

struct UsageSnapshot: Sendable, Equatable {
    /// Claude usage per session id (subagents count toward their parent session).
    var claudeBySession: [String: TokenUsage] = [:]
    var claudeTotal = TokenUsage()
    /// Codex tokens today (Codex logs cumulative totals, so no cost split per model).
    var codexTokens = 0
    var codexLimits: CodexLimits?
}

/// API list prices (USD per million tokens), from the claude-api reference (cached 2026-06-24).
enum ModelPricing {
    struct Price {
        let input: Double
        let output: Double
        /// When nil, cache reads cost 10% of input.
        var cacheRead: Double?
    }

    /// Matched by prefix so dated ids (`claude-haiku-4-5-20251001`) resolve.
    static let prices: [(prefix: String, price: Price)] = [
        ("claude-fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Price(input: 10, output: 50)),
        ("claude-mythos-5", Price(input: 10, output: 50)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25)),
        ("claude-opus-4", Price(input: 5, output: 25)),
        ("claude-sonnet-5", Price(input: 2, output: 10)),
        ("claude-sonnet-4", Price(input: 3, output: 15)),
        ("claude-haiku-4-5", Price(input: 1, output: 5)),
    ]

    static func price(for model: String) -> Price? {
        prices.first { model.hasPrefix($0.prefix) }?.price
    }

    /// Cache writes: 1.25× input for the 5-minute TTL, 2× for 1 hour.
    static func cost(model: String, input: Int, output: Int, cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int) -> Double {
        guard let p = price(for: model) else { return 0 }
        let perToken = 1.0 / 1_000_000
        return (Double(input) * p.input + Double(output) * p.output
            + Double(cacheWrite5m) * p.input * 1.25 + Double(cacheWrite1h) * p.input * 2
            + Double(cacheRead) * (p.cacheRead ?? p.input * 0.1)) * perToken
    }
}

/// Today's token usage from the agents' own logs, read incrementally: each file is followed by
/// byte offset, so after the first pass only appended lines are parsed. Only usage fields are
/// decoded; message content is never kept.
struct UsageTracker: Sendable {
    let claudeRoot: URL
    let codexRoot: URL
    private var day = ""
    private var offsets: [String: UInt64] = [:]
    /// Deduplicated by message id + request id: Claude logs one line per content block, each
    /// repeating the same usage.
    private var claudeEntries: [String: (session: String, usage: TokenUsage)] = [:]
    private var codexFiles: [String: CodexFile] = [:]

    private struct CodexFile: Sendable {
        var totalBeforeToday = 0
        var latestTotal = 0
        var latestLimits: (at: Date, limits: CodexLimits)?
    }

    init(
        claudeRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects"),
        codexRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
    ) {
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
    }

    mutating func update(now: Date = Date(), calendar: Calendar = .current) -> UsageSnapshot {
        let startOfDay = calendar.startOfDay(for: now)
        let today = Self.dayKey(startOfDay, calendar: calendar)
        let startStamp = Self.utcStamp(startOfDay)
        if today != day {  // new day: start over
            day = today
            offsets = [:]
            claudeEntries = [:]
            codexFiles = [:]
        }
        for file in Self.files(under: claudeRoot, modifiedSince: startOfDay) {
            guard let data = newData(of: file) else { continue }
            for entry in Self.claudeEntries(in: data, since: startStamp) {
                claudeEntries[entry.key] = (entry.session, entry.usage)
            }
        }
        for file in Self.files(under: codexRoot, modifiedSince: startOfDay) {
            guard let data = newData(of: file) else { continue }
            Self.forEachLine(in: data, containing: "\"token_count\"") { line in
                ingestCodex(String(decoding: line, as: UTF8.self), file: file.path, since: startOfDay)
            }
        }
        return snapshot()
    }

    private func snapshot() -> UsageSnapshot {
        var result = UsageSnapshot()
        for entry in claudeEntries.values {
            result.claudeBySession[entry.session, default: TokenUsage()] = result.claudeBySession[entry.session, default: TokenUsage()] + entry.usage
            result.claudeTotal = result.claudeTotal + entry.usage
        }
        result.codexTokens = codexFiles.values.reduce(0) { $0 + max(0, $1.latestTotal - $1.totalBeforeToday) }
        result.codexLimits = codexFiles.values.compactMap(\.latestLimits).max { $0.at < $1.at }?.limits
        return result
    }

    // MARK: Claude

    /// Transcripts are large (whole tool results inline), so lines are scanned as bytes and only
    /// a few short fields plus the small `usage` object are decoded. Logs stamp times in UTC
    /// ISO 8601, which compare correctly as strings.
    static func claudeEntries(
        in data: Data, since startStamp: String
    ) -> [(key: String, session: String, usage: TokenUsage)] {
        var result: [(key: String, session: String, usage: TokenUsage)] = []
        forEachLine(in: data, containing: "\"usage\":{") { line in
            guard let timestamp = stringField("timestamp", in: line), timestamp >= startStamp,
                  let usageBytes = objectField("usage", in: line),
                  let usage = try? JSONSerialization.jsonObject(with: usageBytes) as? [String: Any] else { return }
            let key = (stringField("id", in: line, valuePrefix: "msg_") ?? "") + "|" + (stringField("requestId", in: line) ?? "")
            let model = stringField("model", in: line, valuePrefix: "claude-") ?? ""
            result.append((key, stringField("sessionId", in: line) ?? "", claudeUsage(usage, model: model)))
        }
        return result
    }

    /// Calls `body` for every line of `data` that contains `needle`.
    static func forEachLine(in data: Data, containing needle: String, _ body: (UnsafeRawBufferPointer) -> Void) {
        let pattern = Array(needle.utf8)
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            while start < buffer.count {
                let end = memchr(base + start, 0x0A, buffer.count - start).map { base.distance(to: UnsafeRawPointer($0)) } ?? buffer.count
                let line = UnsafeRawBufferPointer(start: base + start, count: end - start)
                if line.count > 0, memmem(line.baseAddress, line.count, pattern, pattern.count) != nil { body(line) }
                start = end + 1
            }
        }
    }

    /// Value of the first `"key":"…"` (optionally starting with `valuePrefix`). Escaped copies inside
    /// string content (`\"key\":\"`) never match.
    static func stringField(_ key: String, in line: UnsafeRawBufferPointer, valuePrefix: String = "") -> String? {
        let pattern = Array("\"\(key)\":\"".utf8) + Array(valuePrefix.utf8)
        guard let base = line.baseAddress, let hit = memmem(base, line.count, pattern, pattern.count) else { return nil }
        let valueStart = base.distance(to: UnsafeRawPointer(hit)) + pattern.count - valuePrefix.utf8.count
        guard let quote = memchr(base + valueStart, 0x22, line.count - valueStart) else { return nil }
        let length = (base + valueStart).distance(to: UnsafeRawPointer(quote))
        return String(decoding: UnsafeRawBufferPointer(start: base + valueStart, count: length), as: UTF8.self)
    }

    /// The `{…}` object after the first `"key":` (usage objects hold no strings with braces).
    static func objectField(_ key: String, in line: UnsafeRawBufferPointer) -> Data? {
        let pattern = Array("\"\(key)\":{".utf8)
        guard let base = line.baseAddress, let hit = memmem(base, line.count, pattern, pattern.count) else { return nil }
        let start = base.distance(to: UnsafeRawPointer(hit)) + pattern.count - 1
        var depth = 0
        for index in start..<line.count {
            switch line[index] {
            case 0x7B: depth += 1
            case 0x7D:
                depth -= 1
                if depth == 0 { return Data(line[start...index]) }
            default: break
            }
        }
        return nil
    }

    static func claudeUsage(_ usage: [String: Any], model: String) -> TokenUsage {
        func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
        let input = int(usage["input_tokens"])
        let output = int(usage["output_tokens"])
        let cacheRead = int(usage["cache_read_input_tokens"])
        let cacheWrite = int(usage["cache_creation_input_tokens"])
        let split = usage["cache_creation"] as? [String: Any]
        let write1h = int(split?["ephemeral_1h_input_tokens"])
        let write5m = split == nil ? cacheWrite : int(split?["ephemeral_5m_input_tokens"])
        return TokenUsage(
            input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead,
            cost: ModelPricing.cost(model: model, input: input, output: output, cacheWrite5m: write5m,
                                    cacheWrite1h: write1h, cacheRead: cacheRead))
    }

    // MARK: Codex

    private mutating func ingestCodex(_ line: String, file: String, since startOfDay: Date) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let timestamp = (object["timestamp"] as? String).flatMap(Self.parseDate) else { return }
        var state = codexFiles[file] ?? CodexFile()
        if let total = ((payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber {
            if timestamp < startOfDay { state.totalBeforeToday = total.intValue }
            state.latestTotal = total.intValue
        }
        if timestamp >= startOfDay, let limits = (payload["rate_limits"] as? [String: Any]).map(Self.codexLimits) {
            state.latestLimits = (timestamp, limits)
        }
        codexFiles[file] = state
    }

    static func codexLimits(_ object: [String: Any]) -> CodexLimits {
        func window(_ key: String) -> CodexLimits.Window? {
            guard let w = object[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else {
                return nil
            }
            return CodexLimits.Window(
                usedPercent: used, windowMinutes: (w["window_minutes"] as? NSNumber)?.intValue ?? 0,
                resetsAt: (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
        }
        return CodexLimits(primary: window("primary"), secondary: window("secondary"))
    }

    // MARK: Files

    /// `.jsonl` files below `root` changed since `date` (older logs cannot hold today's usage).
    static func files(under root: URL, modifiedSince date: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= date {
                result.append(url)
            }
        }
        return result
    }

    /// Bytes of the complete lines appended since the last call; a partial last line waits for
    /// the next pass.
    private mutating func newData(of file: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var offset = offsets[file.path] ?? 0
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {  // truncated or replaced: start over, including Codex totals for it
            offset = 0
            codexFiles[file.path] = nil
        }
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return nil }
        let complete = data[...lastNewline]
        offsets[file.path] = offset + UInt64(complete.count)
        return Data(complete)
    }

    /// `2026-09-24T17:00:00.000Z`, the format the logs use.
    static func utcStamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)
            .timeSeparator(.colon).dateSeparator(.dash).timeZone(separator: .omitted)).replacingOccurrences(of: "+0000", with: "Z")
    }

    private static func parseDate(_ string: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
