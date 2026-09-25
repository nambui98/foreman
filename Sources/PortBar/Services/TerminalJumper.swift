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
            return focusByTTY(script: appleTerminalScript(tty: tty), bundleID: terminalBundleID)
        case .iTerm(let tty):
            return focusByTTY(script: iTermScript(tty: tty), bundleID: iTermBundleID)
        case .app(let name):
            return activate(appNamed: name) ? nil : "Không tìm thấy app \(name)"
        }
    }

    // MARK: Orca

    /// `orca terminal switch` with a fixed executable and argv (no shell); 3s timeout.
    private static func switchOrcaTerminal(handle: String) async -> String? {
        guard TerminalLocator.isValidOrcaHandle(handle) else { return "Terminal handle không hợp lệ" }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: orcaBundleID) else {
            return "Không tìm thấy Orca"
        }
        let cli = app.appending(path: "Contents/Resources/bin/orca")
        return await Task.detached(priority: .userInitiated) {
            runOrcaSwitch(cli: cli, handle: handle)
        }.value
    }

    private nonisolated static func runOrcaSwitch(cli: URL, handle: String) -> String? {
        let process = Process()
        process.executableURL = cli
        process.arguments = ["terminal", "switch", "--terminal", handle, "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return "Không chạy được orca CLI"
        }
        let deadline = DispatchTime.now() + .seconds(3)
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return orcaSwitchError(json: data, exitStatus: process.terminationStatus)
    }

    /// nil when Orca reports `"ok": true`; otherwise a short message for the row.
    nonisolated static func orcaSwitchError(json: Data, exitStatus: Int32) -> String? {
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        if exitStatus == 0, object?["ok"] as? Bool == true { return nil }
        let code = (object?["error"] as? [String: Any])?["code"] as? String
        return "Orca không chuyển được tab" + (code.map { " (\($0))" } ?? "")
    }

    // MARK: Terminal.app / iTerm2

    private static func focusByTTY(script: String, bundleID: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if result?.stringValue == "ok" { return nil }
        activate(bundleID: bundleID)
        if let error, let message = error[NSAppleScript.errorMessage] as? String {
            return "AppleScript: \(message)"
        }
        return "Không thấy tab của agent"
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
