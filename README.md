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

## How it works
- Ports: `/usr/sbin/lsof +c 0 -nP -iTCP -sTCP:LISTEN -F pcun` (fixed argv, 3s timeout).
- CPU / RAM / cwd / argv: libproc (`proc_pid_rusage` phys_footprint + CPU ticks → ns via mach timebase, `PROC_PIDVNODEPATHINFO`, `KERN_PROCARGS2`).
- Refresh: every 2s while the panel is open, every 15s otherwise.

## License
MIT — see [LICENSE](LICENSE).
