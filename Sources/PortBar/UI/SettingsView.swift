import ServiceManagement
import SwiftUI

/// The Settings window (⌘, or the gear in the panel footer).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PortMonitor.self) private var monitor
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Chung") {
                Toggle("Mở PortBar khi đăng nhập", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Cần cho phép trong Cài đặt hệ thống → Mục đăng nhập.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Mở") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            portsSection
            agentsSection
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginStatus = LoginItem.status }
    }

    @ViewBuilder private var portsSection: some View {
        @Bindable var settings = settings
        Section("Cổng") {
            Picker("Mở thư mục bằng", selection: $settings.editorBundleID) {
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
            Stepper("Dev server coi là rảnh sau \(Int(settings.idleHours)) giờ không có kết nối",
                    value: $settings.idleHours, in: 1...72, step: 1)
        }
    }

    @ViewBuilder private var agentsSection: some View {
        @Bindable var settings = settings
        Section("Agents") {
            Toggle("Thông báo khi agent xong việc / chờ bạn", isOn: $settings.notifyEnabled)
                .onChange(of: settings.notifyEnabled) { _, enabled in
                    if enabled { Notifier.requestAuthorization() }
                }
            Stepper("Chỉ báo task dài ≥ \(Int(settings.notifyMinWorkSec))s",
                    value: $settings.notifyMinWorkSec, in: 0...600, step: 10)
                .help("Codex chỉ gửi sự kiện kết thúc (không có lúc bắt đầu) nên luôn được báo.")
            Stepper("Agent không có hook: coi là xong sau \(Int(settings.cpuIdleDebounceSec))s CPU rảnh",
                    value: $settings.cpuIdleDebounceSec, in: 10...300, step: 10)
            snippet("Claude Code — gộp vào ~/.claude/settings.json", AgentEventURL.claudeHooksSnippet)
            snippet("Codex — thêm vào ~/.codex/config.toml", AgentEventURL.codexNotifySnippet)
            LabeledContent("Sự kiện hook gần nhất") {
                Text(monitor.events.lastHookEvent ?? "chưa nhận").foregroundStyle(.secondary)
            }
        }
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
            }
            Text(text).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
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
