import SwiftUI
import VanVatDriveKit

@MainActor struct UploadsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.uploads.items.isEmpty {
                    ContentUnavailableView("No uploads", systemImage: "arrow.up.circle")
                }
                ForEach(model.uploads.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            trailing(item)
                        }
                        if item.state == .uploading || item.state == .queued {
                            ProgressView(value: Double(item.loaded), total: Double(max(item.size, 1)))
                        }
                        Text(status(item)).font(.caption).foregroundStyle(statusColor(item))
                        if case .failed = item.state, isQuotaCode(item.errorCode) { GetMoreResourcesButton().font(.caption) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Uploads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { model.uploads.clearFinished() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func trailing(_ item: UploadQueue.Item) -> some View {
        switch item.state {
        case .queued, .uploading:
            Button { model.uploads.cancel(item.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
        case .failed:
            Button { model.uploads.retry(item.id) } label: { Image(systemName: "arrow.clockwise.circle.fill") }.buttonStyle(.borderless)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .canceled:
            Image(systemName: "slash.circle").foregroundStyle(.secondary)
        }
    }

    private func status(_ item: UploadQueue.Item) -> String {
        switch item.state {
        case .queued: return "Waiting…"
        case .uploading: return "\(Fmt.bytes(item.loaded)) of \(Fmt.bytes(item.size))"
        case .done: return "Uploaded · \(Fmt.bytes(item.size))"
        case .failed(let message): return "Failed: \(message)"
        case .canceled: return "Canceled"
        }
    }

    private func isQuotaCode(_ code: String?) -> Bool {
        guard let code else { return false }
        return DriveError(status: 0, code: code, message: "").isQuotaLimit
    }

    private func statusColor(_ item: UploadQueue.Item) -> Color {
        if case .failed = item.state { return .red }
        return .secondary
    }
}
