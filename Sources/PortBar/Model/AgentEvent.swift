import Foundation

/// Lifecycle events agents report through hooks (`portbar://agent-event?e=<kind>&pid=<pid>`).
enum AgentEventKind: String, Sendable {
    /// A prompt was submitted: the agent starts working (Claude `UserPromptSubmit`).
    case start
    /// The agent finished its turn (Claude `Stop`, Codex `notify`).
    case stop
    /// The agent waits for the user, e.g. a permission prompt (Claude `Notification`).
    case input
}

enum AgentEventURL {
    static let scheme = "portbar"
    static let host = "agent-event"

    /// Any local process can open a `portbar://` URL, so only a known kind and a plausible pid pass;
    /// the pid must still resolve to a running agent of this user before anything happens.
    static func parse(_ url: URL) -> (kind: AgentEventKind, pid: Int32)? {
        guard url.scheme == scheme, url.host() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let kind = items.first(where: { $0.name == "e" })?.value.flatMap(AgentEventKind.init(rawValue:)),
              let pid = items.first(where: { $0.name == "pid" })?.value.flatMap({ Int32($0) }), pid > 1
        else { return nil }
        return (kind, pid)
    }

    /// Hook command for a given event; `$PPID` of the hook shell is the agent (or a wrapper below it).
    static func hookCommand(_ kind: AgentEventKind) -> String {
        "open -g \"\(scheme)://\(host)?e=\(kind.rawValue)&pid=$PPID\""
    }

    /// `hooks` block to merge into `~/.claude/settings.json` (JSON-escaped by the encoder).
    static var claudeHooksSnippet: String {
        let events: [(String, AgentEventKind)] = [("UserPromptSubmit", .start), ("Stop", .stop), ("Notification", .input)]
        var hooks: [String: [[String: [[String: String]]]]] = [:]
        for (name, kind) in events {
            hooks[name] = [["hooks": [["type": "command", "command": hookCommand(kind)]]]]
        }
        return encode(["hooks": hooks])
    }

    /// `notify` line for `~/.codex/config.toml`; Codex only reports finished turns. A JSON array of
    /// strings is also a valid TOML array. Codex appends its JSON payload, which becomes `$1`.
    static var codexNotifySnippet: String {
        "notify = " + encode(["/bin/sh", "-c", hookCommand(.stop), "portbar"], pretty: false)
    }

    private static func encode<T: Encodable>(_ value: T, pretty: Bool = true) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
