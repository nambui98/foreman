import Testing
@testable import PortBar

struct AgentDetectorTests {
    @Test(arguments: [
        ("claude", "/opt/homebrew/bin/claude", [String](), AgentKind?.some(.claude)),
        ("2.1.281", "/Users/me/.local/share/claude/versions/2.1.281", [], .claude),
        ("2.1.281", "/usr/local/bin/2.1.281", [], nil),
        ("codex", "/Applications/Codex.app/Contents/Resources/codex", [], .codex),
        ("cursor-agent", "/Users/me/.local/bin/cursor-agent", [], .cursorAgent),
        ("node", "/opt/homebrew/bin/node", ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"], .claude),
        ("node", "/opt/homebrew/bin/node", ["node", "/usr/local/lib/node_modules/@google/gemini-cli/dist/index.js"], .gemini),
        ("node", "/opt/homebrew/bin/node", ["node", "vite"], nil),
        ("Python", "/usr/bin/python3", ["python3", "/Users/me/.local/bin/aider"], .aider),
        ("zsh", "/bin/zsh", [], nil),
    ])
    func detectsKind(name: String, path: String, args: [String], expected: AgentKind?) {
        #expect(AgentDetector.kind(name: name, path: { path }, arguments: { args }) == expected)
    }

    @Test func nestedAgentsFoldIntoOutermostAndHostComesFromAncestors() {
        // Orca(100) ─ zsh(200) ─ claude(300) ─ zsh(400) ─ claude(500, sub-agent)
        //                                   └ node(600)
        let table = ProcessTable(entries: [
            entry(100, 1, "Orca"), entry(200, 100, "zsh"), entry(300, 200, "2.1.281"),
            entry(400, 300, "zsh"), entry(500, 400, "claude"), entry(600, 300, "node"),
            entry(700, 1, "claude", uid: 0),  // other user's agent is ignored
        ])
        let paths: [Int32: String] = [
            100: "/Applications/Orca.app/Contents/MacOS/Orca",
            300: "/Users/me/.local/share/claude/versions/2.1.281",
        ]
        var cache = AgentDetector.Cache()
        let agents = AgentDetector.agents(
            in: table, currentUID: 501, cache: &cache, path: { paths[$0] },
            arguments: { $0 == 300 ? ["claude", "--agent-id", "angle-altitude@session-1"] : [] })
        #expect(agents.map(\.pid) == [300])
        #expect(agents.first?.kind == .claude)
        #expect(agents.first?.host == "Orca")
        #expect(agents.first?.teamMember == "angle-altitude")

        // Second pass hits the cache: no path/argv lookups needed for known processes.
        var lookups = 0
        let again = AgentDetector.agents(
            in: table, currentUID: 501, cache: &cache,
            path: { lookups += 1; return paths[$0] }, arguments: { _ in lookups += 1; return [] })
        #expect(again == agents)
        #expect(lookups == 0)
    }

    @Test func appNameUsesOutermostBundle() {
        #expect(AgentDetector.appName(fromPath: "/Applications/Orca.app/Contents/Frameworks/Orca Helper.app/Contents/MacOS/Orca Helper") == "Orca")
        #expect(AgentDetector.appName(fromPath: "/bin/zsh") == nil)
        #expect(AgentDetector.appName(fromProcessName: "Orca Helper") == "Orca")
        #expect(AgentDetector.appName(fromProcessName: "Code Helper (Renderer)") == "Code")
        #expect(AgentDetector.appName(fromProcessName: "login") == nil)
    }
}
