import SwiftUI
import VanVatDriveKit

@MainActor struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

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

                Section {
                    Text("The OpenEditz folder at the top of My Drive belongs to the OpenEditz video editor. It is protected: it can't be renamed, moved or deleted, and the editor only works inside it.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("OpenEditz") }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Account")
            .task { await model.refreshMe() }
            .confirmationDialog("Sign out of Van Vat Drive?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            }
        }
    }
}
