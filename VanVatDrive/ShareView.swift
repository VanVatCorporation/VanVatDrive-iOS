import SwiftUI
import VanVatDriveKit

/// People with roles + "Anyone with the link" (view only) + the Direct download switch for single files.
@MainActor struct ShareView: View {
    let node: DriveNode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var info: AccessInfo?
    @State private var identifier = ""
    @State private var role: DriveRole = .viewer
    @State private var expiryHours = 0
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    private let expiryChoices: [(label: String, hours: Int)] = [("Never", 0), ("1 day", 24), ("7 days", 168), ("30 days", 720)]

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }

                if let info {
                    addPeopleSection
                    peopleSection(info)
                    linkSection(info)
                } else if error == nil {
                    Section { ProgressView("Loading…") }
                }
            }
            .navigationTitle("Share “\(node.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await reload() }
        }
    }

    // MARK: Sections

    private var addPeopleSection: some View {
        Section("Add people") {
            TextField("Email or username", text: $identifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
            Picker("Role", selection: $role) {
                ForEach(DriveRole.grantable, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Add") {
                let who = identifier.trimmingCharacters(in: .whitespaces)
                act { try await model.client.grant(node, identifier: who, role: role); identifier = "" }
            }
            .disabled(busy || identifier.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func peopleSection(_ info: AccessInfo) -> some View {
        Section("People with access") {
            HStack {
                Text(info.owner.username ?? "Owner")
                Spacer()
                Text(DriveRole.owner.title).foregroundStyle(.secondary)
            }
            ForEach(info.people) { person in
                HStack {
                    VStack(alignment: .leading) {
                        Text(person.username ?? person.email ?? person.granteeId).lineLimit(1)
                        if let email = person.email, person.username != nil {
                            Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Menu {
                        ForEach(DriveRole.grantable, id: \.self) { r in
                            Button { act { try await model.client.changeRole(permissionId: person.permissionId, to: r) } } label: {
                                if r == person.role { Label(r.title, systemImage: "checkmark") } else { Text(r.title) }
                            }
                        }
                        Divider()
                        Button(role: .destructive) { act { try await model.client.removeAccess(permissionId: person.permissionId) } } label: {
                            Label("Remove access", systemImage: "person.badge.minus")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(person.role.title)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .disabled(busy)
                }
            }
        }
    }

    @ViewBuilder private func linkSection(_ info: AccessInfo) -> some View {
        Section {
            if let link = info.links.first {
                Label("Anyone with the link can view", systemImage: "globe")
                if let exp = link.expiresAt { Text("Expires \(exp.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary) }
                Text(link.url).font(.footnote).textSelection(.enabled).lineLimit(2)
                HStack {
                    Button(copied ? "Copied" : "Copy link", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = link.url
                        copied = true
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                    }
                    Spacer()
                    if let url = URL(string: link.url) { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
                }
                .buttonStyle(.borderless)

                if !node.isFolder {
                    Toggle(isOn: Binding(get: { link.rawServing },
                                         set: { on in act { _ = try await model.client.setRawServing(linkId: link.id, on) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Direct download")
                            Text("Off: the link opens a preview page with a download button. On: the link downloads the file directly.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(busy)
                }

                Button("Restrict access", role: .destructive) {
                    act { for l in info.links { try await model.client.revokeLink(id: l.id) } }
                }
                .disabled(busy)
            } else {
                Label("Restricted", systemImage: "lock")
                Text("Only people with access can open this.").font(.footnote).foregroundStyle(.secondary)
                Picker("Link expires", selection: $expiryHours) {
                    ForEach(expiryChoices.indices, id: \.self) { i in Text(expiryChoices[i].label).tag(expiryChoices[i].hours) }
                }
                Button("Get link") {
                    act { _ = try await model.client.createLink(for: node, expiresInHours: expiryHours == 0 ? nil : expiryHours) }
                }
                .disabled(busy)
            }
        } header: { Text("General access") }
    }

    // MARK: Actions

    private func reload() async {
        do { info = try await model.client.access(of: node); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do { try await work(); await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
}
