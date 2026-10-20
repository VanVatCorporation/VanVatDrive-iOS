import SwiftUI
import VanVatDriveKit

/// Where account tiers are bought. Tiers live on the account (one pack for every Van Vat service), not in Drive.
enum Plans {
    static let url = URL(string: "https://account.vanvatcorp.com/account-center/#plans")!
}

enum QuotaTone {
    case normal, warn, danger

    var color: Color {
        switch self {
        case .normal: return .blue
        case .warn: return .orange
        case .danger: return .red
        }
    }

    /// Same thresholds as the web Drive: below 50% remaining = warn, below 25% remaining = danger.
    static let warnRemainingRatio = 0.50
    static let dangerRemainingRatio = 0.25

    static func of(used: Double, total: Double) -> QuotaTone {
        guard total > 0 else { return .normal }
        let ratio = max(0, total - used) / total
        if ratio < dangerRemainingRatio { return .danger }
        if ratio < warnRemainingRatio { return .warn }
        return .normal
    }
}

/// A progress bar plus a caption, coloured by how much is left.
struct QuotaBar: View {
    let used: Double
    let total: Double
    let label: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(max(used, 0), max(total, 1)), total: max(total, 1))
                .tint(QuotaTone.of(used: used, total: total).color)
            Text(label).font(.footnote).foregroundStyle(.secondary)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 2)
    }
}

/// "Continue anyway" popup shown before an upload/download/preview that probably won't fit today's allowance.
struct QuotaWarning: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onConfirm: () -> Void
    var onCancel: () -> Void = {}
}

extension View {
    func quotaWarning(_ warning: Binding<QuotaWarning?>) -> some View {
        alert(warning.wrappedValue?.title ?? "", isPresented: Binding(
            get: { warning.wrappedValue != nil },
            set: { if !$0 { warning.wrappedValue = nil } }
        ), presenting: warning.wrappedValue) { w in
            Button("Continue anyway", role: .destructive) { w.onConfirm() }
            Button("Cancel", role: .cancel) { w.onCancel() }
        } message: { w in
            Text(w.message)
        }
    }
}

/// The warnings the web Drive shows, with the same wording.
enum QuotaWarnings {
    static func upload(size: Int64, me: Me?, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) -> QuotaWarning? {
        guard let usage = me?.usage, size > usage.uploadFree else { return nil }
        return QuotaWarning(
            title: "Daily upload limit warning",
            message: "You might not have enough daily upload quota left to upload this file (\(Fmt.bytes(size)) selected, only \(Fmt.bytes(usage.uploadFree)) left today). The upload may stop once the limit is reached.",
            onConfirm: onConfirm, onCancel: onCancel)
    }

    static func download(size: Int64, me: Me?, preview: Bool, onConfirm: @escaping () -> Void) -> QuotaWarning? {
        guard let usage = me?.usage, size > usage.downloadFree else { return nil }
        return QuotaWarning(
            title: "Daily download limit warning",
            message: preview
                ? "You might not have enough daily download quota left to preview this file (\(Fmt.bytes(size)) needed, only \(Fmt.bytes(usage.downloadFree)) left today). Previewing uses your daily download allowance."
                : "You might not have enough daily download quota left for this file (\(Fmt.bytes(size)) requested, only \(Fmt.bytes(usage.downloadFree)) left today). The download may be cut off once the limit is reached.",
            onConfirm: onConfirm)
    }
}

/// "Get more resources": opens the account tier upgrade in the browser.
struct GetMoreResourcesButton: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { openURL(Plans.url) } label: { Label("Get more resources", systemImage: "arrow.up.circle") }
    }
}
