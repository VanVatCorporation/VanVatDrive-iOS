import SwiftUI
import VanVatDriveKit

struct LinkToken: Identifiable { let id: String }

@MainActor @Observable
final class AppModel {
    enum Phase { case launching, signedOut, signedIn }

    private(set) var phase: Phase = .launching
    private(set) var me: Me?
    /// Bumped whenever Drive content changed (uploads, moves...). Browser screens reload on it.
    private(set) var changeCounter = 0
    var pendingLink: LinkToken?
    var notice: String?

    let store: KeychainTokenStore
    let account = AccountAuth()
    let client: DriveClient
    let uploads: UploadQueue

    init() {
        let store = KeychainTokenStore()
        self.store = store
        let client = DriveClient(tokenProvider: { store.token })
        client.onTokenRefreshed = { store.token = $0 }
        self.client = client
        self.uploads = UploadQueue(client: client)

        client.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.sessionExpired() }
        }
        // New terms were published while the app was open: /me then reports legal.required and the popup appears.
        client.onTosRequired = { [weak self] in
            Task { @MainActor in await self?.refreshMe() }
        }
        uploads.onItemFinished = { [weak self] _ in self?.contentChanged() }
    }

    // MARK: - Session

    func start() async {
        guard store.token != nil else { phase = .signedOut; return }
        do {
            me = try await client.me()
            phase = .signedIn
        } catch let e as DriveError where e.isUnauthorized {
            signOut()
        } catch {
            phase = .signedIn          // offline: keep the session, screens will show their own errors
        }
    }

    func didSignIn(token: String) async {
        store.token = token
        notice = nil
        await start()
    }

    func signOut() {
        store.clear()
        me = nil
        phase = .signedOut
        try? FileManager.default.removeItem(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VanVatDrive"))
    }

    private func sessionExpired() {
        guard phase == .signedIn else { return }
        signOut()
        notice = "Your session expired. Please sign in again."
    }

    func refreshMe() async {
        if let fresh = try? await client.me() { me = fresh }
    }

    func contentChanged() {
        changeCounter += 1
        Task { await refreshMe() }
    }

    // MARK: - Links

    func handle(url: URL) {
        let parts = url.pathComponents
        if let i = parts.firstIndex(of: "s"), parts.indices.contains(i + 1) {
            pendingLink = LinkToken(id: parts[i + 1])
        }
    }
}
