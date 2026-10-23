import SwiftUI
import VanVatDriveKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .launching: ProgressView("Loading…")
            case .signedOut: LoginView()
            case .signedIn:
                // Until the current Terms of Service / Privacy Policy are accepted, nothing else is reachable.
                if let legal = model.me?.legal, legal.required {
                    TermsGateView(
                        status: legal,
                        loadDocument: { key, lang in try await model.client.legalDocument(key: key, lang: lang) },
                        accept: { versions, lang in try await model.client.acceptLegal(versions: versions, lang: lang) },
                        pageURL: { slug, lang in model.client.legalPageURL(slug: slug, lang: lang) },
                        onAccepted: { await model.refreshMe() })
                } else {
                    MainTabView()
                }
            }
        }
        // A shared link opened from Messages/Safari. Works signed in or out.
        .sheet(item: $model.pendingLink) { link in PublicLinkView(token: link.id) }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            BrowserTab(source: .myDrive)
                .tabItem { Label("My Drive", systemImage: "externaldrive") }
            BrowserTab(source: .shared)
                .tabItem { Label("Shared", systemImage: "person.2") }
            BrowserTab(source: .trash)
                .tabItem { Label("Trash", systemImage: "trash") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}
