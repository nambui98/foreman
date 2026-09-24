import Foundation

enum Formatters {
    static func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func cpu(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        return String(format: percent >= 10 ? "%.0f%%" : "%.1f%%", percent)
    }

    /// `/Users/me/Workspace/app` → `~/Workspace/app`.
    static func abbreviatePath(_ path: String?, home: String = NSHomeDirectory()) -> String? {
        guard let path, path != "/" else { return nil }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
