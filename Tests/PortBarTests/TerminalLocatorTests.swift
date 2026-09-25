import Darwin
import Foundation
import Testing
@testable import PortBar

struct TerminalLocatorTests {
    private let handle = "term_0b37d8d7-744d-4b35-b978-04f9b626492d"

    @Test func orcaUsesTerminalHandle() {
        let env = ["TERM_PROGRAM": "Orca", "ORCA_TERMINAL_HANDLE": handle]
        #expect(TerminalLocator.resolve(environment: env, host: "Orca", tty: "ttys003") == .orca(handle: handle))
    }

    @Test func invalidOrcaHandleFallsBackToHostApp() {
        let env = ["TERM_PROGRAM": "Orca", "ORCA_TERMINAL_HANDLE": "term_x; rm -rf ~"]
        #expect(TerminalLocator.resolve(environment: env, host: "Orca", tty: "ttys003") == .app(name: "Orca"))
    }

    @Test func terminalAndITermMatchByTTY() {
        #expect(TerminalLocator.resolve(environment: ["TERM_PROGRAM": "Apple_Terminal"], host: "Terminal", tty: "ttys012")
                == .appleTerminal(tty: "/dev/ttys012"))
        #expect(TerminalLocator.resolve(environment: ["TERM_PROGRAM": "iTerm.app"], host: "iTerm", tty: "ttys7")
                == .iTerm(tty: "/dev/ttys7"))
        // No tty (e.g. launched by an app) → can only activate the host.
        #expect(TerminalLocator.resolve(environment: ["TERM_PROGRAM": "iTerm.app"], host: "iTerm", tty: nil)
                == .app(name: "iTerm"))
    }

    @Test func unknownHostActivatesAppOrNothing() {
        #expect(TerminalLocator.resolve(environment: ["TERM_PROGRAM": "ghostty"], host: "Ghostty", tty: "ttys001")
                == .app(name: "Ghostty"))
        #expect(TerminalLocator.resolve(environment: [:], host: nil, tty: nil) == nil)
    }

    @Test func ttyValidationRejectsScriptInjection() {
        #expect(TerminalLocator.isValidTTY("/dev/ttys003"))
        #expect(!TerminalLocator.isValidTTY("/dev/ttys003\" then do shell script \"x"))
        #expect(!TerminalLocator.isValidTTY("/dev/console"))
    }

    @Test func scriptsTargetTheTTY() {
        #expect(TerminalJumper.appleTerminalScript(tty: "/dev/ttys004").contains("if tty of t is \"/dev/ttys004\""))
        #expect(TerminalJumper.iTermScript(tty: "/dev/ttys004").contains("if tty of s is \"/dev/ttys004\""))
    }

    @Test func orcaSwitchResultParsing() {
        #expect(TerminalJumper.orcaSwitchError(json: Data(#"{"ok": true}"#.utf8), exitStatus: 0) == nil)
        #expect(TerminalJumper.orcaSwitchError(
            json: Data(#"{"ok": false, "error": {"code": "terminal_handle_stale"}}"#.utf8), exitStatus: 1)
            == "Orca không chuyển được tab (terminal_handle_stale)")
        #expect(TerminalJumper.orcaSwitchError(json: Data(), exitStatus: 15) == "Orca không chuyển được tab")
    }
}

struct ProcessEnvironmentTests {
    @Test func parserKeepsOnlyAllowlistedKeys() {
        var buffer = withUnsafeBytes(of: Int32(2)) { Array($0) }
        buffer += Array("/bin/zsh".utf8) + [0, 0, 0]
        buffer += Array("zsh".utf8) + [0] + Array("-l".utf8) + [0]
        buffer += Array("SECRET_TOKEN=abc".utf8) + [0]
        buffer += Array("TERM_PROGRAM=Orca".utf8) + [0]
        buffer += Array("ORCA_TERMINAL_HANDLE=term_1=2".utf8) + [0, 0]
        let parsed = ProcessInspector.parseProcessArguments(
            buffer[...], environmentKeys: ProcessInspector.terminalEnvironmentKeys)
        #expect(parsed.arguments == ["zsh", "-l"])
        #expect(parsed.environment == ["TERM_PROGRAM": "Orca", "ORCA_TERMINAL_HANDLE": "term_1=2"])

        // Same bytes inside a larger buffer: indices must be relative to the slice.
        let padded = [0xFF, 0xFF, 0xFF] + buffer
        let sliced = ProcessInspector.parseProcessArguments(
            padded[3...], environmentKeys: ProcessInspector.terminalEnvironmentKeys)
        #expect(sliced.arguments == parsed.arguments)
        #expect(sliced.environment == parsed.environment)
    }

    /// macOS hides the environment of Apple platform binaries (e.g. `/bin/sleep`) from other
    /// processes, so the live check reads the test host itself, whose env is known.
    @Test func readsOnlyRequestedKeysOfLiveProcess() {
        let key = "XCTestConfigurationFilePath"
        let env = ProcessInspector.environment(pid: getpid(), keys: [key])
        #expect(env.keys.sorted() == [key])
        #expect(env[key] == ProcessInfo.processInfo.environment[key])
    }
}
