# PortBar

macOS menu bar app that lists every listening TCP port with its process, project folder, CPU% and RAM — and kills it in one click.

Personal-use tool: non-sandboxed, ad-hoc signed, not for the App Store.

## Requirements
- macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Run
```sh
scripts/build-and-run.sh           # Debug build, (re)launch
scripts/build-and-run.sh Release   # Release build, (re)launch
scripts/test.sh                    # unit tests
```
Install: copy `build/Build/Products/Release/PortBar.app` to `~/Applications`.

## Using it
- Sections: **Dev** (node, bun, python, …), **Database / Container** (postgres, redis, OrbStack, …), **Hệ thống** (other apps/daemons, collapsed).
- ✕ sends SIGTERM; if still alive after 3s a **Force** button sends SIGKILL. ⌥-click ✕ = SIGKILL immediately.
- 🧭 opens `http://localhost:PORT` in the browser to see what it is (a menu when there are several ports).
- Right-click a row: kill whole process group (always confirmed, lists members), open `localhost:PORT`, copy PID, open folder in Finder.
- System-section kills ask for confirmation. Other users' / root processes cannot be killed (no privilege escalation).
- A group that contains an interactive terminal shell is never group-killed, so the terminal session survives.
- Leftover dev servers are tagged **mồ côi** (parent exited, or folder deleted — e.g. a removed git worktree) or **rảnh Nh** (no inbound connection, no CPU, older than the idle threshold in Settings, over 3 refreshes). **Dọn (N)** in the header stops the ones you tick: orphans pre-ticked, idle ones not.

## Agents tab
Lists running AI coding agents — Claude Code (incl. Agent Team members), Codex, Cursor Agent, Gemini CLI, Aider, opencode, Goose, Amp — with project folder, host app + tty, uptime, status (working / idle / paused) and CPU/RAM summed over the agent's whole process tree.
- ⏸ **Pause** freezes the agent's child processes (tool commands, MCP servers, dev servers) with SIGSTOP. The agent itself is never stopped: SIGSTOP/SIGCONT on a terminal's foreground job makes the shell take the terminal back and the process dies on its next tty read. Children spawned while paused are paused too; everything is continued when PortBar quits, or on the next launch after a crash.
- ✕ **Stop** sends SIGTERM to the agent and its whole tree (confirmed, lists every process; Force = SIGKILL). Claude/Codex sessions can be reopened with `claude --resume` / `codex resume`.
- Port rows show which agent started them (e.g. `Claude Code · my-app`).
- ↗ **Open terminal** focuses the agent's exact tab: Orca via `orca terminal switch` (tested with Orca 1.4.205), Terminal/iTerm via AppleScript matched by tty (asks for Automation permission once). Other hosts are just brought to the front.

## Notifications
Settings → Agents: a notification when an agent finishes a task (≥ 20s by default) or waits for you; clicking it opens the agent's terminal.
- **Precise (recommended):** add the hooks shown in Settings (Copy button) — Claude Code `UserPromptSubmit` / `Stop` / `Notification` in `~/.claude/settings.json`, Codex `notify` in `~/.codex/config.toml`. Each hook runs `open -g "portbar://agent-event?e=start|stop|input&pid=$PPID"`; PortBar never edits these files.
- **Fallback:** agents without hooks are watched by CPU: a working stretch ≥ 20s followed by 30s of idle CPU counts as done. While such a stretch is timed, agents are re-sampled every 3s (process table only, no lsof).

## How it works
- Ports: `/usr/sbin/lsof +c 0 -nP -iTCP -sTCP:LISTEN,ESTABLISHED -F pcunT` (fixed argv, 3s timeout); established sockets on a listening port count as inbound connections.
- CPU / RAM / cwd / argv: libproc (`proc_pid_rusage` phys_footprint + CPU ticks → ns via mach timebase, `PROC_PIDVNODEPATHINFO`, `KERN_PROCARGS2`).
- Agents: one process-table pass (`proc_listallpids` + libproc, sysctl fallback for root-owned links such as `login`), cached per (pid, start time).
- Refresh: every 2s while the panel is open, every 15s otherwise.

## License
MIT — see [LICENSE](LICENSE).
