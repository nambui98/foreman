import ServiceManagement
import SwiftUI

/// The Settings window (⌘, or the gear in the panel footer): one toolbar tab per area, so the
/// window stays short instead of stacking every section.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Chung", systemImage: "gearshape") { GeneralSettings() }
            Tab("Cổng", systemImage: "network") { PortSettings() }
            Tab("Agents", systemImage: "sparkles") { AgentSettings() }
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
                Toggle("Phím tắt mở panel", isOn: $settings.hotKeyEnabled)
                if settings.hotKeyEnabled {
                    LabeledContent("Tổ hợp phím") { HotKeyRecorder(combo: $settings.hotKey) }
                    if !settings.hotKeyRegistered {
                        Text("Tổ hợp này đang bị app khác dùng — chọn tổ hợp khác.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Section("Menu bar") {
                Picker("Hiển thị", selection: $settings.badgeMode) {
                    ForEach(BadgeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Stepper(value: $settings.ramWarnGB, in: 0...64, step: 1) {
                    LabeledContent("Icon cam khi RAM dev ≥",
                                   value: settings.ramWarnGB > 0 ? "\(Int(settings.ramWarnGB)) GB" : "tắt")
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
                Stepper(value: $settings.idleHours, in: 1...72, step: 1) {
                    LabeledContent("Coi là rảnh sau", value: "\(Int(settings.idleHours)) giờ")
                }
            } footer: {
                Text("Dev server không có kết nối và không dùng CPU quá lâu được gắn nhãn “rảnh”.")
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
                Toggle("Thông báo khi agent xong / chờ bạn", isOn: $settings.notifyEnabled)
                    .onChange(of: settings.notifyEnabled) { _, enabled in
                        if enabled { Notifier.requestAuthorization() }
                    }
                Stepper(value: $settings.notifyMinWorkSec, in: 0...600, step: 10) {
                    LabeledContent("Chỉ báo task dài ≥", value: "\(Int(settings.notifyMinWorkSec))s")
                }
                .help("Codex chỉ gửi sự kiện kết thúc (không có lúc bắt đầu) nên luôn được báo.")
                Stepper(value: $settings.cpuIdleDebounceSec, in: 10...300, step: 10) {
                    LabeledContent("Không có hook: xong sau", value: "\(Int(settings.cpuIdleDebounceSec))s CPU rảnh")
                }
            }
            Section {
                HookRow(name: "Claude Code", file: "~/.claude/settings.json", snippet: AgentEventURL.claudeHooksSnippet)
                HookRow(name: "Codex", file: "~/.codex/config.toml", snippet: AgentEventURL.codexNotifySnippet)
                LabeledContent("Sự kiện gần nhất") {
                    Text(monitor.events.lastHookEvent ?? "chưa nhận").foregroundStyle(.secondary)
                }
            } header: {
                Text("Hook (báo chính xác, tức thì)")
            } footer: {
                Text("Copy rồi gộp vào file cấu hình của agent. PortBar không tự sửa các file này.")
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
                Button(expanded ? "Ẩn" : "Xem") { expanded.toggle() }
                    .buttonStyle(.borderless)
                Button(copied ? "Đã copy" : "Copy") {
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
