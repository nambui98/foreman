import ServiceManagement
import SwiftUI

/// The Settings window (⌘, or the gear in the panel footer).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
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
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
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
