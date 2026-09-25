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

    /// Compact elapsed time: `45s`, `12m`, `2h 44m`, `1d 15h`.
    static func uptime(seconds: Int) -> String {
        let s = max(seconds, 0)
        switch s {
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m"
        case ..<86_400: return "\(s / 3600)h \(s % 3600 / 60)m"
        default: return "\(s / 86_400)d \(s % 86_400 / 3600)h"
        }
    }

    /// `/Users/me/Workspace/app` → `~/Workspace/app`.
    static func abbreviatePath(_ path: String?, home: String = NSHomeDirectory()) -> String? {
        guard let path, path != "/" else { return nil }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// `845K`, `12.3M`, `1.31B` tokens.
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return String(format: "%.0fK", value / 1_000)
        case ..<1_000_000_000: return String(format: value < 10_000_000 ? "%.1fM" : "%.0fM", value / 1_000_000)
        default: return String(format: "%.2fB", value / 1_000_000_000)
        }
    }

    /// `$0.84`, `$18.40`, `$408`.
    static func dollars(_ amount: Double) -> String {
        String(format: amount >= 100 ? "$%.0f" : "$%.2f", amount)
    }
}
