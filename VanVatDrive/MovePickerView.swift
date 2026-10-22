import SwiftUI
import VanVatDriveKit

/// Folder picker. The owner can pick the root ("My Drive"); everyone else only folders they can edit.
/// The server refuses moves between different owners' trees. "Copy to…" uses the same picker: the copy is made on the
/// server (no transfer allowance, it needs free storage); anyone who can see an item may copy it, the root of My Drive
/// is always a valid destination, and so is the same folder (it makes a duplicate).
struct PickerRequest: Identifiable {
    let id = UUID()
    let nodes: [DriveNode]
    let copy: Bool
}

@MainActor struct MovePickerView: View {
    let nodes: [DriveNode]
    var copy = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var currentId: String?
    @State private var listing: Listing?
    @State private var loadError: String?
    @State private var busy = false
    @State private var started = false

    private var ids: Set<String> { Set(nodes.map(\.id)) }
    private var allMine: Bool { nodes.allSatisfy { $0.ownerId == model.me?.userId } }
    /// A move may not leave the owner's tree; a copy always may go to my own root.
    private var isOwner: Bool { copy || allMine }
    private var folders: [DriveNode] { (listing?.items ?? []).filter { $0.isFolder && !ids.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    private var writable: Bool { currentId == nil ? isOwner : (listing?.role.canEdit ?? false) }
    private var canMoveHere: Bool {
        guard writable, listing != nil else { return false }
        if let currentId, ids.contains(currentId) { return false }
        // Moving to where everything already is changes nothing; copying there makes duplicates, which is fine.
        return copy || !nodes.allSatisfy { $0.parentId == currentId }
    }
    private var verb: String { copy ? "Copy" : "Move" }
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
                ToolbarItem(placement: .confirmationAction) { Button("\(verb) here", action: apply).disabled(!canMoveHere || busy) }
            }
            .task {
                guard !started else { return }
                started = true
                // Start next to the item (nil = My Drive root); a copy of somebody else's item starts at My Drive.
                currentId = copy && !allMine ? nil : nodes.first?.parentId
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

    private func apply() {
        Task {
            busy = true
            defer { busy = false }
            var failed = 0
            var first: String?
            for n in nodes {
                do {
                    if copy { _ = try await model.client.copy(n, to: currentId) } else { _ = try await model.client.move(n, to: currentId) }
                } catch {
                    failed += 1
                    if first == nil { first = error.localizedDescription }
                }
            }
            model.contentChanged()
            if copy { await model.refreshMe() }          // the copy used storage
            if failed == 0 { dismiss() } else { loadError = "\(failed) of \(nodes.count) failed: \(first ?? "")" }
        }
    }
}
