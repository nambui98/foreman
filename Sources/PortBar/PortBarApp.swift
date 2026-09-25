import SwiftUI

/// Resumes every process PortBar paused, so quitting never leaves agent tools frozen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = MainActor.assumeIsolated { PortMonitor() }
    let settings = MainActor.assumeIsolated { AppSettings() }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { monitor.agentController.resumeAll() }
    }
}

@main
struct PortBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var monitor: PortMonitor { delegate.monitor }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(monitor)
                .environment(delegate.settings)
        } label: {
            BadgeLabel(count: monitor.devCount)
                .task {
                    // Unit tests use the app as host; don't poll lsof or spawn timers there.
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    monitor.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.settings)
        }
    }
}
