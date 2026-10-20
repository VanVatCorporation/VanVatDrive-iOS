import SwiftUI
import QuickLook
import VanVatDriveKit

/// Downloads the file, then shows it with Quick Look (images, video, audio, PDF, Office files, text...).
@MainActor struct PreviewScreen: View {
    let node: DriveNode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var fileURL: URL?
    @State private var error: String?
    @State private var errorIsQuota = false

    var body: some View {
        NavigationStack {
            Group {
                if let fileURL {
                    QuickLookPreview(url: fileURL).ignoresSafeArea(edges: .bottom)
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't open", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Retry") { Task { await download() } }
                        if errorIsQuota { GetMoreResourcesButton() }
                    }
                } else {
                    VStack(spacing: 12) { ProgressView(); Text("Downloading…").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(node.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let fileURL { ToolbarItem(placement: .primaryAction) { ShareLink(item: fileURL) } }
            }
            .task { await download() }
        }
    }

    private func download() async {
        error = nil
        errorIsQuota = false
        do {
            fileURL = try await model.client.download(node)
            await model.refreshMe()          // the preview used part of today's download allowance
        } catch {
            self.error = error.localizedDescription
            errorIsQuota = (error as? DriveError)?.isQuotaLimit ?? false
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
