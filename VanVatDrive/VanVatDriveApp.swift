import SwiftUI
import VanVatDriveKit

@main
struct VanVatDriveApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                // https://drive.vanvatcorp.com/s/<token>  (needs the Associated Domains capability, see README)
                .onOpenURL { model.handle(url: $0) }
        }
    }
}
