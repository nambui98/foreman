import Foundation

/// What Claude Code itself reports about a running session in `~/.claude/sessions/<pid>.json`.
struct ClaudeSession: Sendable, Equatable {
    enum Status: String, Sendable {
        case busy, shell, idle
    }

    let pid: Int32
    let sessionId: String
    let status: Status?
    let cwd: String?
}

/// Reads Claude Code's per-process session files. Each file is re-parsed only when it changes;
/// only the pid, session id, status and cwd are decoded.
struct ClaudeSessionReader: Sendable {
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions")

    let directory: URL
    private var cache: [String: (modifiedAt: Date, session: ClaudeSession?)] = [:]

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// Sessions keyed by the agent's pid.
    mutating func sessions() -> [Int32: ClaudeSession] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var fresh: [String: (modifiedAt: Date, session: ClaudeSession?)] = [:]
        var result: [Int32: ClaudeSession] = [:]
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            let session: ClaudeSession?
            if let cached = cache[file.lastPathComponent], cached.modifiedAt == modified {
                session = cached.session
            } else {
                session = (try? Data(contentsOf: file)).flatMap(Self.parse)
            }
            fresh[file.lastPathComponent] = (modified, session)
            if let session { result[session.pid] = session }
        }
        cache = fresh
        return result
    }

    private struct File: Decodable {
        let pid: Int32
        let sessionId: String
        let status: String?
        let cwd: String?
    }

    static func parse(_ data: Data) -> ClaudeSession? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return ClaudeSession(
            pid: file.pid, sessionId: file.sessionId,
            status: file.status.flatMap(ClaudeSession.Status.init(rawValue:)), cwd: file.cwd)
    }
}

/// Short task titles Claude Code gives its terminal tab (`✳ Fix login redirect`), read through
/// `orca terminal list`. The leading status glyph is dropped.
enum OrcaTerminalTitles {
    static func list(orcaCLI: URL) -> [String: String]? {
        guard let result = ProcessRunner.run(orcaCLI, ["terminal", "list", "--json"], timeout: .seconds(3)),
              result.status == 0 else { return nil }
        return parse(result.output)
    }

    /// Handle → cleaned title.
    static func parse(_ json: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let terminals = (object["result"] as? [String: Any])?["terminals"] as? [[String: Any]] else { return [:] }
        var titles: [String: String] = [:]
        for terminal in terminals {
            guard let handle = terminal["handle"] as? String, let raw = terminal["title"] as? String,
                  let title = clean(raw) else { continue }
            titles[handle] = title
        }
        return titles
    }

    /// `✳ Fix login redirect` → `Fix login redirect`; generic titles (`Claude Code`) and folder
    /// names Codex shows (`..ct/landingpro`) are not task titles.
    static func clean(_ title: String) -> String? {
        let trimmed = title.drop { !$0.isLetter && !$0.isNumber }.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "Claude Code", !title.hasPrefix("..") else { return nil }
        return trimmed
    }
}
