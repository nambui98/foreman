import ServiceManagement
import SwiftUI

/// The Settings window (⌘, or the gear in the panel footer): one toolbar tab per area, so the
/// window stays short instead of stacking every section.
struct SettingsView: View {
    var body: some View {
        // tabItem (not the macOS 15 `Tab` API) keeps Settings working on macOS 14.
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            PortSettings().tabItem { Label("Ports", systemImage: "network") }
            AgentSettings().tabItem { Label("Agents", systemImage: "sparkles") }
        }
        .frame(width: 460)
    }
}

/// Grouped form that sizes the window to its content.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section {
                Picker("Language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text(verbatim: $0.name).tag($0) }
                }
                if settings.language != settings.launchLanguage {
                    HStack {
                        Text("Restart Foreman to apply the new language.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart") { AppDelegate.relaunch() }
                    }
                }
            }
            Section {
                Toggle("Open Foreman at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Needs approval in System Settings → Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Shortcut to open the panel", isOn: $settings.hotKeyEnabled)
                if settings.hotKeyEnabled {
                    LabeledContent("Shortcut") { HotKeyRecorder(combo: $settings.hotKey) }
                    if !settings.hotKeyRegistered {
                        Text("Another app uses this shortcut — record a different one.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Section("Menu bar") {
                Picker("Show", selection: $settings.badgeMode) {
                    ForEach(BadgeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Stepper(value: $settings.ramWarnGB, in: 0...64, step: 1) {
                    LabeledContent("Orange icon when dev RAM ≥",
                                   value: settings.ramWarnGB > 0 ? "\(Int(settings.ramWarnGB)) GB" : String(localized: "off"))
                }
            }
        }
        .onAppear { loginStatus = LoginItem.status }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = LoginItem.status
    }
}

private struct PortSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section {
                Picker("Open folders with", selection: $settings.editorBundleID) {
                    ForEach(EditorLauncher.installed()) { editor in
                        Text(editor.name).tag(Optional(editor.bundleID))
                    }
                }
                .onAppear {
                    // Also replaces a saved editor that has since been uninstalled.
                    let installed = EditorLauncher.installed()
                    if !installed.contains(where: { $0.bundleID == settings.editorBundleID }) {
                        settings.editorBundleID = installed.first?.bundleID
                    }
                }
                Stepper(value: $settings.idleHours, in: 1...72, step: 1) {
                    LabeledContent("Idle after", value: String(localized: "\(Int(settings.idleHours)) h"))
                }
            } footer: {
                Text("Dev servers with no connections and no CPU for this long are tagged “idle”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AgentSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PortMonitor.self) private var monitor

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section {
                Toggle("Keep the Mac awake while an agent works", isOn: $settings.keepAwake)
                    .help("Prevents idle sleep only while an agent is working; the display can still turn off.")
                Toggle("Notify when an agent finishes or waits for you", isOn: $settings.notifyEnabled)
                    .onChange(of: settings.notifyEnabled) { _, enabled in
                        if enabled { Notifier.requestAuthorization() }
                    }
                Stepper(value: $settings.notifyMinWorkSec, in: 0...600, step: 10) {
                    LabeledContent("Only for tasks of at least", value: "\(Int(settings.notifyMinWorkSec))s")
                }
                .help("Codex reports only the end of a turn (no start), so every Codex turn notifies.")
                Stepper(value: $settings.cpuIdleDebounceSec, in: 10...300, step: 10) {
                    LabeledContent("Without hooks: done after", value: String(localized: "\(Int(settings.cpuIdleDebounceSec))s of idle CPU"))
                }
            }
            Section {
                HookRow(name: "Claude Code", file: "~/.claude/settings.json", snippet: AgentEventURL.claudeHooksSnippet)
                HookRow(name: "Codex", file: "~/.codex/config.toml", snippet: AgentEventURL.codexNotifySnippet)
                LabeledContent("Last event") {
                    Text(monitor.events.lastHookEvent ?? String(localized: "none yet")).foregroundStyle(.secondary)
                }
            } header: {
                Text("Hooks (exact, instant)")
            } footer: {
                Text("Copy and merge into the agent's config file. Foreman never edits these files.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One agent's hook: name, target file and Copy; the snippet itself stays folded.
private struct HookRow: View {
    let name: String
    let file: String
    let snippet: String
    @State private var copied = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    Text(file).font(.caption).foregroundStyle(.secondary).monospaced()
                }
                Spacer()
                Button(expanded ? String(localized: "Hide") : String(localized: "View")) { expanded.toggle() }
                    .buttonStyle(.borderless)
                Button(copied ? String(localized: "Copied") : String(localized: "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
            }
            if expanded {
                ScrollView {
                    Text(snippet).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            }
        }
    }
}
