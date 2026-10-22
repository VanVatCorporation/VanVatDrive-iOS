import SwiftUI
import PhotosUI
import VanVatDriveKit

enum BrowserSource: Hashable {
    case myDrive, shared, trash

    var title: String {
        switch self {
        case .myDrive: return "My Drive"
        case .shared: return "Shared with me"
        case .trash: return "Trash"
        }
    }
}

struct FolderRoute: Hashable {
    let id: String
    let name: String
}

/// One tab = one NavigationStack; folders push more BrowserViews.
struct BrowserTab: View {
    let source: BrowserSource
    @State private var path: [FolderRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            BrowserView(source: source, folder: nil)
                .navigationDestination(for: FolderRoute.self) { BrowserView(source: source, folder: $0) }
        }
    }
}

private enum SortKey: String, CaseIterable, Identifiable {
    case name = "Name", modified = "Last modified", size = "Size"
    var id: String { rawValue }
}

@MainActor struct BrowserView: View {
    let source: BrowserSource
    let folder: FolderRoute?

    @Environment(AppModel.self) private var model

    @State private var items: [DriveNode] = []
    @State private var role: DriveRole = .owner
    @State private var sharedMeta: [String: SharedItem] = [:]
    @State private var loading = true
    @State private var loadError: String?
    @State private var query = ""
    @State private var sort: SortKey = .name

    @State private var showFolderAlert = false
    @State private var newFolderName = "Untitled folder"
    @State private var renaming: DriveNode?
    @State private var renameText = ""
    @State private var sharing: DriveNode?
    @State private var picker: PickerRequest?
    @State private var previewing: DriveNode?
    @State private var purging: DriveNode?
    @State private var confirmEmpty = false
    @State private var showUploads = false
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var alertMessage: String?
    @State private var warning: QuotaWarning?
    // multi-select + ZIP download
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var zipping = false
    @State private var zipShare: SharedFile?

    private var sharedRoot: Bool { source == .shared && folder == nil }
    private var canCreate: Bool {
        switch source {
        case .myDrive: return folder == nil || role.canEdit
        case .shared: return folder != nil && role.canEdit
        case .trash: return false
        }
    }

    private var visible: [DriveNode] {
        let filtered = query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified: return a.updatedAt > b.updatedAt
            case .size: return a.size > b.size
            }
        }
    }

    var body: some View {
        content
            .navigationTitle(folder?.name ?? source.title)
            .navigationBarTitleDisplayMode(folder == nil ? .large : .inline)
            .searchable(text: $query, prompt: "Search in this folder")
            .toolbar { toolbarContent }
            .toolbar { selectionBar }
            .task(id: model.changeCounter) { await load() }
            .refreshable { await load() }
            // dialogs
            .alert("New folder", isPresented: $showFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createFolder() }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") { rename() }
            }
            .quotaWarning($warning)
            .alert("Drive", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMessage ?? "") }
            .confirmationDialog("Delete forever?", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }), titleVisibility: .visible) {
                Button("Delete forever", role: .destructive) { if let n = purging { run { try await model.client.purge(n) } } }
            } message: { Text("“\(purging?.name ?? "")” cannot be recovered.") }
            .confirmationDialog("Empty trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
                Button("Empty trash", role: .destructive) { run { try await model.client.emptyTrash() } }
            } message: { Text("Everything in the trash is deleted forever.") }
            // sheets
            .sheet(item: $sharing) { ShareView(node: $0) }
            .sheet(item: $picker) { MovePickerView(nodes: $0.nodes, copy: $0.copy) }
            .sheet(isPresented: $showUploads) { UploadsView() }
            .sheet(item: $zipShare) { ActivityView(url: $0.url) }
            .toolbar(selecting ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom) { if selecting { selectionActionBar } }
            .overlay { if zipping { ProgressView("Preparing ZIP…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
            .fullScreenCover(item: $previewing) { PreviewScreen(node: $0) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { enqueue(Importers.copyIntoSandbox(urls)) }
            }
            .onChange(of: photoItems) { _, picked in importPhotos(picked) }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if loading && items.isEmpty {
            ProgressView("Loading…").frame(maxHeight: .infinity)
        } else if let loadError, items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: { Text(loadError) } actions: {
                Button("Retry") { Task { await load() } }
            }
        } else if visible.isEmpty {
            ContentUnavailableView(query.isEmpty ? emptyTitle : "No results", systemImage: source == .trash ? "trash" : "folder",
                                   description: Text(query.isEmpty ? emptyHint : "Nothing matches “\(query)”."))
        } else {
            List(visible) { node in
                row(node)
                    .contextMenu { menu(node) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipe(node) }
            }
            .listStyle(.plain)
        }
    }

    private var emptyTitle: String {
        switch source {
        case .myDrive: return "This folder is empty"
        case .shared: return "Nothing shared yet"
        case .trash: return "Trash is empty"
        }
    }
    private var emptyHint: String {
        switch source {
        case .myDrive: return canCreate ? "Tap + to add files or a folder." : ""
        case .shared: return "Files and folders other people share with you appear here."
        case .trash: return "Items in the trash are deleted forever after 30 days."
        }
    }

    @ViewBuilder private func row(_ node: DriveNode) -> some View {
        if selecting {
            Button { toggle(node) } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(node.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(node.id) ? Color.accentColor : .secondary)
                        .imageScale(.large)
                    NodeRow(node: node, sharedBy: sharedMeta[node.id]?.sharedBy, showDeleted: source == .trash, thumbnails: thumbnailsOn)
                }
            }
            .buttonStyle(.plain)
        } else if node.isFolder && source != .trash {
            NavigationLink(value: FolderRoute(id: node.id, name: node.name)) {
                NodeRow(node: node, sharedBy: sharedMeta[node.id]?.sharedBy, thumbnails: thumbnailsOn)
            }
        } else {
            Button { open(node) } label: {
                NodeRow(node: node, sharedBy: sharedMeta[node.id]?.sharedBy, showDeleted: source == .trash, thumbnails: thumbnailsOn)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Menus

    @ViewBuilder private func menu(_ node: DriveNode) -> some View {
        if source == .trash {
            Button { run { try await model.client.restore(node) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { purging = node } label: { Label("Delete forever", systemImage: "trash") }
        } else {
            if !node.isFolder { Button { open(node) } label: { Label("Open", systemImage: "eye") } }
            if node.isFolder { Button { downloadZip([node]) } label: { Label("Download as ZIP", systemImage: "arrow.down.circle") } }
            Button { selecting = true; selection = [node.id] } label: { Label("Select", systemImage: "checkmark.circle") }
            if node.myRole.canManage { Button { sharing = node } label: { Label("Share", systemImage: "person.badge.plus") } }
            if node.myRole.canEdit && !node.isSystemFolder {
                Button { renameText = node.name; renaming = node } label: { Label("Rename", systemImage: "pencil") }
                if !sharedRoot { Button { picker = PickerRequest(nodes: [node], copy: false) } label: { Label("Move to…", systemImage: "folder") } }
            }
            // Copying needs no edit rights on the original (read access is enough); system folders cannot be copied.
            if !node.isSystemFolder { Button { picker = PickerRequest(nodes: [node], copy: true) } label: { Label("Copy to…", systemImage: "doc.on.doc") } }
            if sharedRoot, let pid = sharedMeta[node.id]?.permissionId {
                Button(role: .destructive) { run { try await model.client.removeAccess(permissionId: pid) } } label: {
                    Label("Remove from Shared", systemImage: "xmark.circle")
                }
            } else if node.myRole.canEdit && !node.isSystemFolder {
                Button(role: .destructive) { run { try await model.client.trash(node) } } label: { Label("Move to trash", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder private func swipe(_ node: DriveNode) -> some View {
        if source == .trash {
            Button(role: .destructive) { purging = node } label: { Label("Delete", systemImage: "trash") }
            Button { run { try await model.client.restore(node) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }.tint(.blue)
        } else {
            if sharedRoot, let pid = sharedMeta[node.id]?.permissionId {
                Button(role: .destructive) { run { try await model.client.removeAccess(permissionId: pid) } } label: { Label("Remove", systemImage: "xmark") }
            } else if node.myRole.canEdit && !node.isSystemFolder {
                Button(role: .destructive) { run { try await model.client.trash(node) } } label: { Label("Trash", systemImage: "trash") }
            }
            if node.myRole.canManage { Button { sharing = node } label: { Label("Share", systemImage: "person.badge.plus") }.tint(.blue) }
        }
    }

    // MARK: - Toolbar

    /// Selection mode: Cancel / count at the top, bulk actions at the bottom.
    @ToolbarContentBuilder private var selectionBar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(selection.count == visible.count ? "Select none" : "Select all") {
                    selection = selection.count == visible.count ? [] : Set(visible.map(\.id))
                }
            }
            ToolbarItem(placement: .principal) { Text(selection.isEmpty ? "Select items" : "\(selection.count) selected").font(.headline) }
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { selecting = false; selection = [] } }
        }
    }

    /// The actions for the selection, as a bar above the keyboard-safe area (the tab bar hides while selecting).
    private var selectionActionBar: some View {
        HStack(alignment: .top, spacing: 0) {
            actionButton("Download", "arrow.down.circle", enabled: !selection.isEmpty && source != .trash) { downloadZip(selectedNodes) }
            if canEditSelection { actionButton("Move to…", "folder", enabled: !selection.isEmpty) { picker = PickerRequest(nodes: selectedNodes, copy: false) } }
            if canCopySelection { actionButton("Copy to…", "doc.on.doc", enabled: !selection.isEmpty) { picker = PickerRequest(nodes: selectedNodes, copy: true) } }
            if canEditSelection { actionButton("Trash", "trash", enabled: !selection.isEmpty, destructive: true) { trashSelected() } }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func actionButton(_ title: String, _ symbol: String, enabled: Bool, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)
    }

    /// Image thumbnails follow the account's "Preview thumbnails" setting; never in the trash.
    private var thumbnailsOn: Bool { source != .trash && (model.me?.previewThumbnails ?? true) }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if !selecting { ToolbarItemGroup(placement: .topBarTrailing) {
            if model.uploads.activeCount > 0 || !model.uploads.items.isEmpty {
                Button { showUploads = true } label: {
                    Image(systemName: model.uploads.activeCount > 0 ? "arrow.up.circle.fill" : "arrow.up.circle")
                }
            }
            if source == .trash {
                if !items.isEmpty { Button("Empty") { confirmEmpty = true } }
            } else {
                Menu {
                    Button { selecting = true; selection = [] } label: { Label("Select", systemImage: "checkmark.circle") }
                    Picker("Sort by", selection: $sort) { ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Image(systemName: "arrow.up.arrow.down") }

                if canCreate {
                    Menu {
                        Button { newFolderName = "Untitled folder"; showFolderAlert = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                        Button { importing = true } label: { Label("Upload files", systemImage: "doc.badge.plus") }
                        PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos])) {
                            Label("Upload photos & videos", systemImage: "photo.badge.plus")
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
        } }
    }

    // MARK: - Actions

    private func load() async {
        loadError = nil
        do {
            switch (source, folder) {
            case (.trash, _):
                items = try await model.client.trash()
                role = .owner
            case (.shared, nil):
                let shared = try await model.client.shared()
                items = shared.map(\.node)
                sharedMeta = Dictionary(uniqueKeysWithValues: shared.map { ($0.node.id, $0) })
                role = .viewer
            default:
                let listing = try await model.client.list(parentId: folder?.id)
                items = listing.items
                role = listing.role
            }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code != .cancelled { loadError = error.localizedDescription }
        }
        loading = false
    }

    // MARK: Selection + ZIP

    private var selectedNodes: [DriveNode] { visible.filter { selection.contains($0.id) } }

    /// Trashing needs edit rights on everything selected, outside the Shared root and not on protected system folders.
    private var canCopySelection: Bool {
        source != .trash && !selection.isEmpty && selectedNodes.allSatisfy { !$0.isSystemFolder }
    }

    private var canEditSelection: Bool {
        source == .myDrive || (source == .shared && folder != nil)
            ? !selection.isEmpty && selectedNodes.allSatisfy { $0.myRole.canEdit && !$0.isSystemFolder }
            : false
    }

    private func toggle(_ node: DriveNode) {
        if selection.contains(node.id) { selection.remove(node.id) } else { selection.insert(node.id) }
    }

    private func trashSelected() {
        let nodes = selectedNodes
        selecting = false
        selection = []
        run { for n in nodes { try await model.client.trash(n) } }
    }

    /// Plans the ZIP first (what it costs today), warns if it probably won't fit, then streams it and opens the share sheet.
    private func downloadZip(_ nodes: [DriveNode]) {
        guard !nodes.isEmpty else { return }
        let ids = nodes.map(\.id)
        Task {
            do {
                let plan = try await model.client.zipPlan(ids: ids)
                let go = { startZip(ids) }
                if let w = QuotaWarnings.zip(plan: plan, me: model.me, onConfirm: go) { warning = w } else { go() }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func startZip(_ ids: [String]) {
        zipping = true
        Task {
            defer { zipping = false }
            do {
                let url = try await model.client.downloadZip(ids: ids)
                await model.refreshMe()               // the ZIP spent part of today's download + compute allowance
                selecting = false
                selection = []
                zipShare = SharedFile(url: url)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); model.contentChanged() }
            catch { alertMessage = error.localizedDescription }
        }
    }

    private func open(_ node: DriveNode) {
        guard !node.isFolder, source != .trash else { return }
        // Opening a file downloads it, so it spends the daily download allowance: warn first if it won't fit.
        if let w = QuotaWarnings.download(size: node.size, me: model.me, preview: true, onConfirm: { previewing = node }) {
            warning = w
            return
        }
        previewing = node
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run { _ = try await model.client.createFolder(parentId: folder?.id, name: name) }
    }

    private func rename() {
        guard let node = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty, name != node.name else { return }
        run { _ = try await model.client.rename(node, to: name) }
    }

    private func enqueue(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let total = urls.reduce(Int64(0)) { sum, url in
            sum + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        let discard = { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        // Items in someone else's folder use THEIR space, so only check my own storage when I own the destination.
        if let me = model.me, role == .owner, total > me.storageFree {
            discard()
            alertMessage = "Not enough space: you have \(Fmt.bytes(me.storageFree)) left of \(Fmt.bytes(me.quotaBytes)). Use “Get more resources” in Account to upgrade."
            return
        }
        let start = {
            model.uploads.add(fileURLs: urls, parentId: folder?.id)
            showUploads = true
        }
        if let w = QuotaWarnings.upload(size: total, me: model.me, onConfirm: start, onCancel: discard) {
            warning = w
            return
        }
        start()
    }

    private func importPhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        photoItems = []
        Task {
            var urls: [URL] = []
            for item in picked {
                if let file = try? await item.loadTransferable(type: PickedFile.self) { urls.append(file.url) }
            }
            enqueue(urls)
        }
    }
}
