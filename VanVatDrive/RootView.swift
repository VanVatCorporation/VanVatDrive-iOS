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
            case .signedIn: MainTabView()
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
