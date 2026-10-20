import SwiftUI
import VanVatDriveKit

/// Opens https://drive.vanvatcorp.com/s/<token> inside the app (the app is the "preview page"). No login needed.
@MainActor struct PublicLinkView: View {
    let token: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var meta: PublicMeta?
    @State private var stack: [PublicNode] = []
    @State private var items: [PublicNode] = []
    @State private var error: String?
    @State private var working: String?
    @State private var shareURL: URL?
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Link unavailable", systemImage: "link.badge.plus", description: Text(error))
                } else if let meta {
                    if meta.node.isFolder { folderList(meta.node) } else { fileCard(meta.node) }
                } else {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle(stack.last?.name ?? meta?.node.name ?? "Shared link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !stack.isEmpty { ToolbarItem(placement: .primaryAction) { Button("Up") { up() } } }
            }
            .task { await start() }
            .fullScreenCover(item: Binding(get: { preview.map(IdentifiedURL.init) }, set: { if $0 == nil { preview = nil } })) { wrapper in
                NavigationStack {
                    QuickLookPreview(url: wrapper.url).ignoresSafeArea(edges: .bottom)
                        .navigationTitle(wrapper.url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { preview = nil } }
                            ToolbarItem(placement: .primaryAction) { ShareLink(item: wrapper.url) }
                        }
                }
            }
        }
    }

    private struct IdentifiedURL: Identifiable, Equatable { let url: URL; var id: URL { url } }

    private func fileCard(_ node: PublicNode) -> some View {
        VStack(spacing: 14) {
            Image(systemName: node.kind.symbol).font(.system(size: 64)).foregroundStyle(node.kind.tint)
            Text(node.name).font(.title3.bold()).multilineTextAlignment(.center)
            Text("\(Fmt.bytes(node.size)) · \(Fmt.date(node.updatedAt))").foregroundStyle(.secondary)
            if let working { ProgressView(working) }
            Button { Task { await open(node) } } label: { Label("Open", systemImage: "eye").frame(maxWidth: 240) }
                .buttonStyle(.borderedProminent).disabled(working != nil)
        }
        .padding()
    }

    private func folderList(_ root: PublicNode) -> some View {
        List(items) { node in
            Button {
                if node.isFolder { Task { await enter(node) } } else { Task { await open(node) } }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: node.kind.symbol).foregroundStyle(node.kind.tint).frame(width: 30)
                    VStack(alignment: .leading) {
                        Text(node.name).lineLimit(1)
                        Text(node.isFolder ? Fmt.date(node.updatedAt) : "\(Fmt.date(node.updatedAt)) · \(Fmt.bytes(node.size))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if node.isFolder { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                }
            }
            .buttonStyle(.plain)
        }
        .overlay { if let working { ProgressView(working).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .overlay { if items.isEmpty { ContentUnavailableView("Empty folder", systemImage: "folder") } }
    }

    private func start() async {
        do {
            let m = try await model.client.publicMeta(token: token)
            meta = m
            if m.node.isFolder { items = try await model.client.publicList(token: token).items }
        } catch { self.error = "This link is invalid or has expired." }
    }

    private func enter(_ folder: PublicNode) async {
        do {
            items = try await model.client.publicList(token: token, parentId: folder.id).items
            stack.append(folder)
        } catch { self.error = error.localizedDescription }
    }

    private func up() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        Task {
            do { items = try await model.client.publicList(token: token, parentId: stack.last?.id).items }
            catch { self.error = error.localizedDescription }
        }
    }

    private func open(_ node: PublicNode) async {
        working = "Downloading…"
        defer { working = nil }
        do { preview = try await model.client.publicDownload(token: token, node: node) }
        catch { self.error = error.localizedDescription }
    }
}
