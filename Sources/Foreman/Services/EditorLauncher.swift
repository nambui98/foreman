import AppKit

/// A code editor Foreman can open a folder in.
struct Editor: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

@MainActor
enum EditorLauncher {
    static let known: [Editor] = [
        Editor(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        Editor(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        Editor(bundleID: "dev.zed.Zed", name: "Zed"),
        Editor(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        Editor(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
    ]

    static func installed() -> [Editor] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// The editor chosen in Settings, else the first installed one.
    static func preferred(bundleID: String?) -> Editor? {
        let editors = installed()
        return editors.first { $0.bundleID == bundleID } ?? editors.first
    }

    static func open(folder: String, in editor: Editor) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: app,
            configuration: NSWorkspace.OpenConfiguration())
    }
}
