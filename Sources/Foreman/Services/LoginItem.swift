import ServiceManagement

/// Launch at login via `SMAppService.mainApp`. The system owns the state, so it is always read back
/// instead of cached. Ad-hoc signed builds change identity on every rebuild: after reinstalling,
/// the registration may need to be toggled off and on again.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
