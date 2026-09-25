import AppKit
import Foundation

/// Brings an agent's terminal tab to the front.
@MainActor
enum TerminalJumper {
    nonisolated static let orcaBundleID = "com.stablyai.orca"
    nonisolated static let terminalBundleID = "com.apple.Terminal"
    nonisolated static let iTermBundleID = "com.googlecode.iterm2"

    /// Focuses the tab; returns an error message when only the host app could be activated.
    static func jump(to locator: TerminalLocator) async -> String? {
        switch locator {
        case .orca(let handle):
            let error = await switchOrcaTerminal(handle: handle)
            activate(bundleID: orcaBundleID)
            return error
        case .appleTerminal(let tty):
            return await focusByTTY(script: appleTerminalScript(tty: tty), bundleID: terminalBundleID)
        case .iTerm(let tty):
            return await focusByTTY(script: iTermScript(tty: tty), bundleID: iTermBundleID)
        case .app(let name):
            return activate(appNamed: name) ? nil : String(localized: "App \(name) not found")
        }
    }

    // MARK: Orca

    /// `orca terminal switch` with a fixed executable and argv (no shell); 3s timeout.
    private static func switchOrcaTerminal(handle: String) async -> String? {
        guard TerminalLocator.isValidOrcaHandle(handle) else { return String(localized: "Invalid terminal handle") }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: orcaBundleID) else {
            return String(localized: "Orca not found")
        }
        let cli = app.appending(path: "Contents/Resources/bin/orca")
        return await Task.detached(priority: .userInitiated) {
            runOrcaSwitch(cli: cli, handle: handle)
        }.value
    }

    private nonisolated static func runOrcaSwitch(cli: URL, handle: String) -> String? {
        guard let result = ProcessRunner.run(cli, ["terminal", "switch", "--terminal", handle, "--json"]) else {
            return String(localized: "Couldn't run the orca CLI")
        }
        return orcaSwitchError(json: result.output, exitStatus: result.status)
    }

    /// nil when Orca reports `"ok": true`; otherwise a short message for the row.
    nonisolated static func orcaSwitchError(json: Data, exitStatus: Int32) -> String? {
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        if exitStatus == 0, object?["ok"] as? Bool == true { return nil }
        let code = (object?["error"] as? [String: Any])?["code"] as? String
        return String(localized: "Orca couldn't switch tabs") + (code.map { " (\($0))" } ?? "")
    }

    // MARK: Terminal.app / iTerm2

    /// `osascript` in a background task: a first-use Automation prompt or a busy terminal app must
    /// not freeze the menu bar UI (the Apple Events are still attributed to Foreman). The 10s limit
    /// leaves time to answer that prompt; the script itself gives up after 3s.
    private static func focusByTTY(script: String, bundleID: String) async -> String? {
        let result = await Task.detached(priority: .userInitiated) {
            ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script], timeout: .seconds(10))
        }.value
        if let result, result.status == 0,
           String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
            return nil
        }
        activate(bundleID: bundleID)
        return result?.status == 0 ? String(localized: "Agent's tab not found")
            : String(localized: "AppleScript failed (Automation permission needed?)")
    }

    /// `tty` is validated as `/dev/ttysNNN` by `TerminalLocator`, so interpolation is safe.
    nonisolated static func appleTerminalScript(tty: String) -> String {
        """
        with timeout of 3 seconds
            tell application id "\(terminalBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return "notfound"
        """
    }

    nonisolated static func iTermScript(tty: String) -> String {
        """
        with timeout of 3 seconds
            tell application id "\(iTermBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end timeout
        return "notfound"
        """
    }

    // MARK: Activation

    @discardableResult
    private static func activate(bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        return app.activate()
    }

    /// Matches the host name `AgentDetector` derived from the bundle path (`Ghostty` ← `Ghostty.app`).
    private static func activate(appNamed name: String) -> Bool {
        let app = NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.deletingPathExtension().lastPathComponent == name || $0.localizedName == name
        }
        return app?.activate() ?? false
    }
}
