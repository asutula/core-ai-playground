import SwiftUI

enum Format {
    static func size(mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    static func gb(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    static func params(_ b: Double?) -> String {
        guard let b else { return "—" }
        if b < 1 { return String(format: "%.0fM", b * 1000) }
        return String(format: "%.1fB", b)
    }
}

extension CompatibilityEngine.Verdict {
    var color: Color {
        switch self {
        case .recommended: return .green
        case .capable:     return .blue
        case .tight:       return .orange
        case .unsupported: return .red
        }
    }

    var symbol: String {
        switch self {
        case .recommended: return "checkmark.seal.fill"
        case .capable:     return "checkmark.circle.fill"
        case .tight:       return "exclamationmark.triangle.fill"
        case .unsupported: return "xmark.octagon.fill"
        }
    }
}

extension CompatibilityEngine.CheckStatus {
    var color: Color {
        switch self {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .info: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// Small pill showing a model's verdict.
struct VerdictBadge: View {
    let verdict: CompatibilityEngine.Verdict
    var compact = false

    var body: some View {
        Label {
            if !compact { Text(verdict.label).font(.caption.weight(.semibold)) }
        } icon: {
            Image(systemName: verdict.symbol)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(verdict.color)
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(verdict.color.opacity(0.14), in: Capsule())
    }
}
