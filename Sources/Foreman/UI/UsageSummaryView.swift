import SwiftUI

/// Today's agent usage above the Agents list: Claude tokens and their API-price equivalent, Codex
/// tokens and its plan limits.
struct UsageSummaryView: View {
    let usage: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Today").font(.caption.weight(.semibold))
                if usage.claudeTotal.total > 0 {
                    Text(verbatim: "Claude \(Formatters.tokens(usage.claudeTotal.total)) · ≈ \(Formatters.dollars(usage.claudeTotal.cost))")
                        .help("Token counts from Claude Code transcripts, priced at API list prices. A Claude subscription is not billed per token.")
                }
                if usage.codexTokens > 0 {
                    Text(verbatim: "Codex \(Formatters.tokens(usage.codexTokens))")
                }
                Spacer()
            }
            .font(.caption).monospacedDigit()
            if let limits = usage.codexLimits {
                HStack(spacing: 10) {
                    if let primary = limits.primary { LimitGauge(label: window(primary), window: primary) }
                    if let secondary = limits.secondary { LimitGauge(label: window(secondary), window: secondary) }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// `Codex 5h`, `Codex week`.
    private func window(_ window: CodexLimits.Window) -> String {
        switch window.windowMinutes {
        case 10_080: String(localized: "Codex week")
        case let minutes where minutes % 60 == 0: String(localized: "Codex \(minutes / 60)h")
        default: String(localized: "Codex \(window.windowMinutes)m")
        }
    }
}

/// `Codex 5h ▓▓░░░ 12%`, orange above 80%.
private struct LimitGauge: View {
    let label: String
    let window: CodexLimits.Window

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: label).font(.caption2).foregroundStyle(.secondary)
            Gauge(value: min(window.usedPercent, 100), in: 0...100) {}
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(window.usedPercent >= 80 ? .orange : .accentColor)
                .frame(width: 54)
            Text(verbatim: "\(Int(window.usedPercent))%").font(.caption2).monospacedDigit()
        }
        .help(window.resetsAt.map { String(localized: "Resets \($0.formatted(date: .abbreviated, time: .shortened))") } ?? "")
    }
}
