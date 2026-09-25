/// Finds agent CLIs in a process table.
enum AgentDetector {
    /// Per-process results keyed by (pid, start time); path/argv lookups are the expensive part
    /// and a process's identity never changes, so each is resolved once.
    struct Cache: Sendable {
        struct Key: Hashable, Sendable {
            let pid: Int32
            let startSec: UInt64
        }
        struct Resolved: Sendable {
            let kind: AgentKind?
            /// Host and team member are looked up once per agent, even when not found.
            var detailsResolved = false
            var host: String?
            var teamMember: String?
            var tty: String?
        }
        var resolved: [Key: Resolved] = [:]
    }

    /// Identifies an agent by kernel name, falling back to the executable path (native Claude Code
    /// binaries are named after their version) and argv (npm-installed CLIs run under node/bun).
    static func kind(name: String, path: () -> String?, arguments: () -> [String]) -> AgentKind? {
        if let kind = AgentKind(rawValue: name) { return kind }

        if !name.isEmpty, name.allSatisfy({ $0.isNumber || $0 == "." }) {
            return path()?.contains("/claude/versions/") == true ? .claude : nil
        }

        let lower = name.lowercased()
        let runtimes: Set<String> = ["node", "bun", "deno"]
        if runtimes.contains(lower) || lower.hasPrefix("python") {
            let argv = arguments().joined(separator: " ")
            if argv.contains("@anthropic-ai/claude-code") { return .claude }
            if argv.contains("@openai/codex") { return .codex }
            if argv.contains("@google/gemini-cli") { return .gemini }
            if argv.contains("/bin/aider") || argv.contains(" -m aider") { return .aider }
        }
        return nil
    }

    static func agents(
        in table: ProcessTable,
        currentUID: UInt32,
        cache: inout Cache,
        path: (Int32) -> String?,
        arguments: (Int32) -> [String]
    ) -> [AgentProcess] {
        var fresh = Cache()
        var kinds: [Int32: AgentKind] = [:]
        for entry in table.entries.values where entry.uid == currentUID {
            let key = Cache.Key(pid: entry.pid, startSec: entry.startSec)
            let resolved = cache.resolved[key] ?? Cache.Resolved(
                kind: kind(name: entry.name, path: { path(entry.pid) }, arguments: { arguments(entry.pid) }))
            fresh.resolved[key] = resolved
            if let kind = resolved.kind { kinds[entry.pid] = kind }
        }

        let result = kinds.compactMap { pid, kind -> AgentProcess? in
            let ancestors = table.ancestors(of: pid)
            // Sub-agents spawned by another agent belong to the outermost one.
            guard !ancestors.contains(where: { kinds[$0] != nil }), let entry = table.entries[pid] else {
                return nil
            }
            let key = Cache.Key(pid: pid, startSec: entry.startSec)
            var resolved = fresh.resolved[key]!
            if !resolved.detailsResolved {
                resolved.detailsResolved = true
                for candidate in ancestors + [pid] {
                    // proc_pidpath can fail for some app helpers; their kernel name still identifies them.
                    let host = path(candidate).flatMap(appName(fromPath:))
                        ?? table.entries[candidate].flatMap { appName(fromProcessName: $0.name) }
                    if let host {
                        resolved.host = host
                        break
                    }
                }
                resolved.teamMember = teamMember(arguments: arguments(pid))
                // devname() consults the device database — slow enough to cache.
                resolved.tty = ProcessInspector.ttyName(device: entry.ttyDevice)
                fresh.resolved[key] = resolved
            }
            return AgentProcess(
                pid: pid, kind: kind, startSec: entry.startSec,
                tty: resolved.tty, host: resolved.host,
                teamMember: resolved.teamMember)
        }
        .sorted { $0.pid < $1.pid }
        cache = fresh  // drops exited processes
        return result
    }

    /// `--agent-id angle-altitude@session-12fa8667` → `angle-altitude`.
    static func teamMember(arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--agent-id"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1].split(separator: "@").first.map(String.init)
    }

    /// `Orca Helper` / `Code Helper (Renderer)` → `Orca` / `Code`; nil for plain processes.
    static func appName(fromProcessName name: String) -> String? {
        guard let range = name.range(of: " Helper") else { return nil }
        let app = String(name[..<range.lowerBound])
        return app.isEmpty ? nil : app
    }

    /// `/Applications/Orca.app/Contents/MacOS/Orca` → `Orca` (outermost bundle wins for helpers).
    static func appName(fromPath path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return path[..<range.lowerBound].split(separator: "/").last.map(String.init)
    }
}
