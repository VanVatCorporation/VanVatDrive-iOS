import SwiftUI
import VanVatDriveKit

@MainActor struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var thumbnailsOverride: Bool?         // shown immediately while the server saves it
    @State private var settingsError: String?

    private var thumbnails: Bool { thumbnailsOverride ?? model.me?.previewThumbnails ?? true }

    /// Flips immediately, rolls back if the server refuses (same as the web).
    private func setThumbnails(_ on: Bool) {
        thumbnailsOverride = on
        Task {
            do { try await model.client.updateSettings(previewThumbnails: on) }
            catch { settingsError = error.localizedDescription }
            await model.refreshMe()
            thumbnailsOverride = nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Name", value: model.me?.username ?? "—")
                    LabeledContent("Email", value: model.me?.email ?? "—")
                }

                if let me = model.me {
                    Section {
                        if let plan = me.plan {
                            LabeledContent("Plan", value: plan.name)
                        }
                        QuotaBar(used: Double(me.usedBytes), total: Double(me.quotaBytes),
                                 label: "\(Fmt.bytes(me.usedBytes)) of \(Fmt.bytes(me.quotaBytes)) used")
                        if let max = me.maxFileBytes {
                            LabeledContent("Largest file", value: Fmt.bytes(max))
                        }
                    } header: { Text("Storage") }

                    if let usage = me.usage {
                        Section {
                            let reset = "Resets \(usage.resetsAt.formatted(date: .abbreviated, time: .shortened))"
                            QuotaBar(used: Double(usage.uploadedBytes), total: Double(usage.uploadLimit),
                                     label: "Uploaded today: \(Fmt.bytes(usage.uploadedBytes)) of \(Fmt.bytes(usage.uploadLimit))", caption: reset)
                            QuotaBar(used: Double(usage.downloadedBytes), total: Double(usage.downloadLimit),
                                     label: "Downloaded today: \(Fmt.bytes(usage.downloadedBytes)) of \(Fmt.bytes(usage.downloadLimit))", caption: reset)
                            if let limit = usage.computeLimit {
                                QuotaBar(used: usage.computeUsed ?? 0, total: limit,
                                         label: "Compute today: \(Fmt.credits(usage.computeUsed ?? 0)) of \(Fmt.credits(limit)) credits", caption: reset)
                            }
                        } header: { Text("Daily limits") } footer: {
                            Text("Preview and download count toward your daily download allowance. Compute is shared with every Van Vat service.")
                        }
                    }

                    Section { GetMoreResourcesButton() }
                }

                Section("Legal") {
                    Link(destination: model.client.legalPageURL(slug: "terms", lang: nil)) { Label("Terms of Service", systemImage: "doc.text") }
                    Link(destination: model.client.legalPageURL(slug: "privacy", lang: nil)) { Label("Privacy Policy", systemImage: "hand.raised") }
                }

                Section {
                    Toggle("Preview thumbnails", isOn: Binding(get: { thumbnails }, set: { setThumbnails($0) }))
                } header: { Text("Preferences") } footer: {
                    Text("Shows small previews of your images in folders. Every preview downloads the image once, so it uses your daily download allowance. Turn it off to save that allowance.")
                }

                Section {
                    Text("The OpenEditz folder at the top of My Drive belongs to the OpenEditz video editor. It is protected: it can't be renamed, moved or deleted, and the editor only works inside it.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("OpenEditz") }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Account")
            .alert("Settings", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(settingsError ?? "") }
            .task { await model.refreshMe() }
            .confirmationDialog("Sign out of Van Vat Drive?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            }
        }
    }
}
