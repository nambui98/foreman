import SwiftUI

/// Owns the long-lived services; resumes every process PortBar paused on quit, receives
/// `portbar://` URLs from agent hooks and delivers notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let monitor: PortMonitor
    private var notifier: Notifier?
    private var hotKey: HotKey?

    override init() {
        let settings = MainActor.assumeIsolated { AppSettings() }
        self.settings = settings
        monitor = MainActor.assumeIsolated { PortMonitor(settings: settings) }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host: no notification center there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        MainActor.assumeIsolated {
            let notifier = Notifier()
            notifier.onOpen = { [monitor] member in Task { await monitor.openAgent(member) } }
            monitor.events.post = { notifier.post($0) }
            if settings.notifyEnabled { Notifier.requestAuthorization() }
            self.notifier = notifier
            applyHotKey()
        }
    }

    /// (Re)registers the global shortcut whenever its settings change.
    @MainActor private func applyHotKey() {
        withObservationTracking {
            hotKey = settings.hotKeyEnabled ? HotKey(settings.hotKey) { PanelToggler.toggle() } : nil
            settings.hotKeyRegistered = !settings.hotKeyEnabled || hotKey != nil
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyHotKey() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                Task { await monitor.handleAgentEvent(url) }
            }
        }
    }

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
            BadgeLabel(count: monitor.devCount, memoryBytes: monitor.devMemoryBytes,
                       mode: delegate.settings.badgeMode, warnGB: delegate.settings.ramWarnGB)
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
                .environment(monitor)
        }
    }
}
