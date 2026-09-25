/// AI coding agent CLIs Foreman recognises. Raw value = executable / argv[0] name.
enum AgentKind: String, CaseIterable, Sendable {
    case claude, codex, cursorAgent = "cursor-agent", gemini, aider, opencode, goose, amp

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursorAgent: "Cursor Agent"
        case .gemini: "Gemini CLI"
        case .aider: "Aider"
        case .opencode: "opencode"
        case .goose: "Goose"
        case .amp: "Amp"
        }
    }

    /// Command that continues a stopped session, when the CLI supports it.
    var resumeHint: String? {
        switch self {
        case .claude: "claude --resume"
        case .codex: "codex resume"
        case .gemini: "gemini --resume"
        default: nil
        }
    }
}

/// A top-level agent process (nested agents are folded into their outermost ancestor).
struct AgentProcess: Sendable, Equatable {
    let pid: Int32
    let kind: AgentKind
    let startSec: UInt64
    let tty: String?
    /// App hosting the agent's terminal, e.g. `Orca`, `Terminal`, `Codex`.
    let host: String?
    /// Agent Team member name from `--agent-id <name>@<team>`, if any.
    var teamMember: String? = nil
    /// How to focus the agent's terminal tab, when it can be located.
    var terminal: TerminalLocator? = nil
    /// Orca pane (`ORCA_PANE_KEY`), the key of Orca's per-pane agent status.
    var orcaPaneKey: String? = nil
}
