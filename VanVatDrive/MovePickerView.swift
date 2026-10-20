import SwiftUI
import VanVatDriveKit

/// Folder picker. The owner can pick the root ("My Drive"); everyone else only folders they can edit.
/// The server refuses moves between different owners' trees.
@MainActor struct MovePickerView: View {
    let node: DriveNode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var currentId: String?
    @State private var listing: Listing?
    @State private var loadError: String?
    @State private var busy = false
    @State private var started = false

    private var isOwner: Bool { node.ownerId == model.me?.userId }
    private var folders: [DriveNode] { (listing?.items ?? []).filter { $0.isFolder && $0.id != node.id }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    private var writable: Bool { currentId == nil ? isOwner : (listing?.role.canEdit ?? false) }
    private var canMoveHere: Bool { writable && currentId != node.parentId && currentId != node.id && listing != nil }
    private var title: String { listing?.path.last?.name ?? (currentId == nil ? "My Drive" : "…") }

    var body: some View {
        NavigationStack {
            List {
                if let parent = listing?.path.dropLast().last {
                    Button { go(parent.id) } label: { Label("Up to “\(parent.name)”", systemImage: "arrow.turn.left.up") }
                } else if currentId != nil, isOwner, (listing?.path.count ?? 0) == 1 {
                    Button { go(nil) } label: { Label("Up to My Drive", systemImage: "arrow.turn.left.up") }
                }
                if let loadError { Text(loadError).foregroundStyle(.red).font(.footnote) }
                if listing == nil && loadError == nil { ProgressView() }
                if listing != nil && folders.isEmpty { Text("No folders here").foregroundStyle(.secondary) }
                ForEach(folders) { f in
                    Button { go(f.id) } label: {
                        HStack { Image(systemName: "folder.fill").foregroundStyle(.gray); Text(f.name); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Move here", action: move).disabled(!canMoveHere || busy) }
            }
            .task {
                guard !started else { return }
                started = true
                currentId = node.parentId          // start next to the item (nil = My Drive root, owner only)
                await load()
            }
        }
    }

    private func go(_ id: String?) {
        currentId = id
        Task { await load() }
    }

    private func load() async {
        listing = nil
        loadError = nil
        do { listing = try await model.client.list(parentId: currentId) }
        catch { loadError = error.localizedDescription }
    }

    private func move() {
        Task {
            busy = true
            defer { busy = false }
            do {
                _ = try await model.client.move(node, to: currentId)
                model.contentChanged()
                dismiss()
            } catch { loadError = error.localizedDescription }
        }
    }
}
