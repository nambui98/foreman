<p align="center"><img src="design/banner.png" alt="Foreman — every port, every AI coding agent, and what they leave running, watched from your macOS menu bar" width="880"></p>

# Foreman

**A macOS menu bar foreman for your dev machine.** One panel shows every listening port, every AI coding agent, and what they left running — and lets you stop, pause, clean up or jump to any of it.

- **Ports** — every listening TCP port with its process, project, framework, git branch, CPU and RAM. Stop anything in one click.
- **Agents** — Claude Code, Codex, Cursor Agent, Gemini CLI, Aider and more, with live status, CPU, RAM and today's tokens and cost. Pause, stop, or jump to the agent's terminal tab.
- **Usage** — today's tokens at API prices, and how full your Codex limits are.
- **Clean-up** — finds dev servers left behind by closed terminals and removed worktrees, and stops them after you confirm.

Website: <https://foreman-relay.nambvbottoken.workers.dev>

## Download

**Requirements:** macOS 14 Sonoma or later, Apple silicon or Intel.

1. From the [latest release](https://github.com/nambui98/foreman/releases/latest), download the disk image for your Mac:
   | Your Mac | File |
   |---|---|
   | Apple silicon (M1, M2, M3, M4…) | `Foreman-<version>-apple-silicon.dmg` |
   | Intel | `Foreman-<version>-intel.dmg` |
   | Not sure / several Macs | `Foreman-<version>-universal.dmg` (runs on both) |
2. Open the `.dmg` and drag **Foreman** onto **Applications**.
3. Releases up to 1.4.1 are ad-hoc signed, not notarized, so macOS blocks the first launch. Open it once with right-click → **Open** (on macOS 15+: System Settings → Privacy & Security → **Open Anyway**), or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Foreman.app
   ```

## Help and feedback

Report bugs and ask questions in [Issues](https://github.com/nambui98/foreman/issues).

## Source code

This repository hosts releases. The source of Foreman 1.4.1 and earlier stays available under the MIT License in this repository's history and tags (for example [`v1.4.1`](https://github.com/nambui98/foreman/tree/v1.4.1)). Later versions are closed source.
